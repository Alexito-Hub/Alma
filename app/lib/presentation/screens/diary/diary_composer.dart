part of 'diary_screen.dart';

// The composer: text, mood, photos, clips, a voice note, a place.

class _Composer extends StatefulWidget {
  const _Composer({
    required this.dayLabel,
    required this.sending,
    required this.onSubmit,
    required this.onClose,
  });
  final String dayLabel;
  final bool sending;
  final ValueChanged<EntryDraft> onSubmit;
  final VoidCallback onClose;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _body = TextEditingController();
  final _link = TextEditingController();
  String? _mood;
  final List<String> _photos = [];
  final List<String> _videos = [];
  bool _private = false;
  GeoTag? _geo;
  bool _locating = false;

  /// Where a picked photo says it was taken, read from its EXIF.
  ///
  /// Offered, never applied on its own: the entry's place is the couple's to
  /// choose, and a photo can carry a fix from somewhere they don't mean —
  /// a screenshot, a picture of a picture, something forwarded to them.
  GeoTag? _photoGeo;

  // Voice note: hold the mic to record, release to keep the take.
  final _recorder = VoiceRecorder();
  String? _audioPath;
  bool _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    _body.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_recording) return;
    final path = await _recorder.start();
    if (path == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Necesito permiso del micrófono')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _stopRecording({bool keep = true}) async {
    if (!_recording) return;
    _ticker?.cancel();
    final path = keep ? await _recorder.stop() : null;
    if (!keep) await _recorder.cancel();
    if (!mounted) return;
    setState(() {
      _recording = false;
      // Takes under a second are almost always an accidental tap.
      if (keep && path != null && _elapsed.inMilliseconds >= 400) {
        _audioPath = path;
      }
      _elapsed = Duration.zero;
    });
  }

  /// Photos go in exactly as the camera made them.
  ///
  /// This used to pass `imageQuality: 88`, which is not a hint — it makes
  /// image_picker re-encode the JPEG before handing it over ("if null, the
  /// image will be returned with the original quality"). Every memory was
  /// getting a second lossy pass, and the metadata the camera wrote — when
  /// and where the photo was taken — did not survive it. Nothing here is
  /// worth that; the diary is the copy of record.
  Future<void> _pickPhotos() async {
    final shots = await ImagePicker().pickMultiImage();
    if (shots.isEmpty) return;
    final paths = shots.map((x) => x.path).toList();
    setState(() => _photos.addAll(paths));
    await _offerPhotoLocation(paths);
  }

  Future<void> _pickVideo() async {
    final v = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (v != null) setState(() => _videos.add(v.path));
  }

  /// If one of the just-picked photos knows where it was taken, hold on to it
  /// so the composer can offer it. Silent when nothing carries a fix.
  Future<void> _offerPhotoLocation(List<String> paths) async {
    if (_geo != null || _photoGeo != null) return;
    for (final path in paths) {
      final exif = await readPhotoExif(File(path));
      if (exif == null || !exif.hasLocation) continue;
      final label = await MediaTools.describeCoordinates(
        exif.latitude!,
        exif.longitude!,
      );
      if (!mounted) return;
      setState(() {
        _photoGeo = GeoTag(
          latitude: exif.latitude!,
          longitude: exif.longitude!,
          label: label,
        );
      });
      return;
    }
  }

  Future<void> _addLocation() async {
    setState(() => _locating = true);
    final geo = await MediaTools.captureLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _geo = geo;
    });
    if (geo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo obtener la ubicación')),
      );
    }
  }

  void _submit() {
    if (_body.text.trim().isEmpty) return;
    widget.onSubmit(
      EntryDraft(
        body: _body.text,
        mood: _mood,
        link: _link.text.trim().isEmpty ? null : _link.text.trim(),
        imagePaths: List.of(_photos),
        videoPaths: List.of(_videos),
        audioPath: _audioPath,
        geo: _geo,
        private: _private,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    final maxH = MediaQuery.of(context).size.height * 0.62;
    return Container(
      decoration: const BoxDecoration(
        color: Neo.paper,
        border: Border(
          top: BorderSide(color: Neo.ink, width: Neo.stroke),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        MediaQuery.of(context).viewInsets.bottom + 14,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const NeoIconBadge(
                    icon: Icons.edit_rounded,
                    color: Neo.pink,
                    size: 30,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ESCRIBIR · ${widget.dayLabel}',
                      style: txt.labelMedium?.copyWith(letterSpacing: 1.2),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  NeoIconButton(
                    icon: Icons.close_rounded,
                    size: 40,
                    iconSize: 20,
                    onPressed: widget.onClose,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Mood (emoji is fine here).
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final m in _moods)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _mood = _mood == m ? null : m),
                          child: Container(
                            width: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _mood == m ? Neo.mint : Neo.white,
                              border: Neo.borderThin,
                              borderRadius: Neo.cornerSm,
                            ),
                            child: Text(
                              m,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Lo que sientes ahora, o lo que quieres recordar…',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _link,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: 'Enlace (opcional): canción, artículo…',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
              ),
              const SizedBox(height: 12),
              // Attachment previews.
              if (_photos.isNotEmpty) _photoStrip(),
              for (var i = 0; i < _videos.length; i++)
                _attachmentChip(
                  Icons.movie_rounded,
                  _videos.length == 1 ? 'Vídeo adjunto' : 'Vídeo ${i + 1}',
                  Neo.sky,
                  () => setState(() => _videos.removeAt(i)),
                ),
              if (_audioPath != null)
                _attachmentChip(
                  Icons.mic_rounded,
                  'Nota de voz',
                  Neo.coral,
                  () => setState(() => _audioPath = null),
                ),
              if (_geo != null)
                _attachmentChip(
                  Icons.place_rounded,
                  _geo!.label ?? 'Ubicación',
                  Neo.mint,
                  () => setState(() => _geo = null),
                ),
              if (_geo == null && _photoGeo != null) _photoPlaceOffer(),
              // Attachment buttons — replaced by the recorder while taping.
              if (_recording) _recordingBar(),
              if (!_recording)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _attachBtn(
                      Icons.add_photo_alternate_outlined,
                      'Fotos',
                      _pickPhotos,
                    ),
                    _attachBtn(Icons.videocam_rounded, 'Vídeo', _pickVideo),
                    _attachBtn(
                      Icons.place_rounded,
                      _locating ? '…' : 'Ubicación',
                      _addLocation,
                    ),
                    _attachBtn(
                      Icons.mic_rounded,
                      'Nota de voz',
                      _startRecording,
                    ),
                    NeoChip(
                      icon: _private
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      label: _private ? 'Privada' : 'Normal',
                      selected: _private,
                      color: Neo.rose,
                      onTap: () => setState(() => _private = !_private),
                    ),
                  ],
                ),
              const SizedBox(height: 14),
              NeoButton(
                label: 'Guardar',
                icon: Icons.check_rounded,
                expand: true,
                busy: widget.sending,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shown in place of the attach buttons while a take is running, so it's
  /// obvious that the mic is live and how to keep or drop it.
  Widget _recordingBar() {
    final txt = Theme.of(context).textTheme;
    return NeoBox(
      width: double.infinity,
      color: Neo.coral,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      shadowOffset: Neo.shadowSm,
      child: Row(
        children: [
          const Icon(
            Icons.fiber_manual_record_rounded,
            size: 15,
            color: Neo.ink,
          ),
          const SizedBox(width: 8),
          Text(_clock(_elapsed), style: txt.labelLarge),
          const Spacer(),
          NeoButton(
            label: 'Descartar',
            color: Neo.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            shadowOffset: Neo.shadowSm,
            textStyle: txt.labelSmall,
            onPressed: () => _stopRecording(keep: false),
          ),
          const SizedBox(width: 8),
          NeoButton(
            label: 'Listo',
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shadowOffset: Neo.shadowSm,
            textStyle: txt.labelSmall,
            onPressed: _stopRecording,
          ),
        ],
      ),
    );
  }

  static String _clock(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _attachBtn(IconData icon, String label, VoidCallback onTap) {
    return NeoButton(
      label: label,
      icon: icon,
      color: Neo.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shadowOffset: Neo.shadowSm,
      textStyle: Theme.of(context).textTheme.labelSmall,
      onPressed: onTap,
    );
  }

  /// "This photo knows where it was taken" — an offer, with a way to say no.
  ///
  /// Deliberately not the same shape as an attachment chip: nothing has been
  /// added to the entry yet, and it shouldn't look as if it had.
  Widget _photoPlaceOffer() {
    final geo = _photoGeo!;
    final txt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: Neo.white,
          border: Neo.borderThin,
          borderRadius: Neo.cornerSm,
        ),
        child: Row(
          children: [
            const Icon(Icons.photo_camera_back_outlined, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('La foto recuerda dónde fue', style: txt.labelSmall),
                  Text(
                    geo.label ??
                        '${geo.latitude.toStringAsFixed(4)}, '
                            '${geo.longitude.toStringAsFixed(4)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: txt.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            NeoButton(
              label: 'Usar',
              color: Neo.mint,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shadowOffset: Neo.shadowSm,
              onPressed: () => setState(() {
                _geo = _photoGeo;
                _photoGeo = null;
              }),
            ),
            GestureDetector(
              onTap: () => setState(() => _photoGeo = null),
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.close_rounded, size: 18, color: Neo.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attachmentChip(
    IconData icon,
    String label,
    Color color,
    VoidCallback onRemove,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: color,
          border: Neo.borderThin,
          borderRadius: Neo.cornerSm,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Neo.ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: Neo.ink),
              ),
            ),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close_rounded, size: 18, color: Neo.ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoStrip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 72,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final p in _photos)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(
                  children: [
                    NeoFrame(
                      width: 72,
                      height: 72,
                      child: Image.file(File(p), fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => setState(() => _photos.remove(p)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Neo.ink,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 13,
                            color: Neo.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
