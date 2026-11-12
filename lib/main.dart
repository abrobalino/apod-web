import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'youtube_embed_stub.dart'
    if (dart.library.js_interop) 'youtube_embed_web.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    fvp.registerWith();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NASA Foto del Día',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090D16),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
          surface: const Color(0xFF131B2E),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF131B2E),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF090D16),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      home: const ApodPage(),
    );
  }
}

/// Servicio de traducción rápido y gratuito (Google Translate con fallback MyMemory)
class TranslationService {
  static final Map<String, String> _cache = {};

  static Future<String> translateToSpanish(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;
    if (_cache.containsKey(trimmed)) {
      return _cache[trimmed]!;
    }

    // 1. Google Translate API pública (en Web usa proxy /api/translate en el mismo origen)
    try {
      final uri = kIsWeb
          ? Uri.parse('/api/translate?q=${Uri.encodeComponent(trimmed)}')
          : Uri.parse(
              'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=es&dt=t&q=${Uri.encodeComponent(trimmed)}',
            );
      final response = kIsWeb
          ? await http.get(uri).timeout(const Duration(seconds: 8))
          : await http.get(
              uri,
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              },
            ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List && decoded.isNotEmpty && decoded[0] is List) {
          final buffer = StringBuffer();
          for (final item in decoded[0]) {
            if (item is List && item.isNotEmpty && item[0] != null) {
              buffer.write(item[0].toString());
            }
          }
          final result = buffer.toString().trim();
          if (result.isNotEmpty) {
            _cache[trimmed] = result;
            return result;
          }
        }
      }
    } catch (e) {
      debugPrint('Error en Google Translate API: $e. Probando fallback...');
    }

    // 2. Fallback: MyMemory Translation API
    try {
      final fallbackResult = await _translateWithMyMemory(trimmed);
      if (fallbackResult.isNotEmpty) {
        _cache[trimmed] = fallbackResult;
        return fallbackResult;
      }
    } catch (e) {
      debugPrint('Error en MyMemory fallback: $e');
    }

    throw Exception('No se pudo traducir en este momento. Inténtalo de nuevo.');
  }

  static Future<String> _translateWithMyMemory(String text) async {
    if (text.length <= 450) {
      final uri = Uri.parse(
        'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(text)}&langpair=en|es',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final translated = data['responseData']?['translatedText']?.toString();
        if (translated != null && translated.isNotEmpty) return translated;
      }
      return '';
    }

    // Dividir en fragmentos menores a 450 caracteres si es necesario
    final sentences = text.split('. ');
    final chunks = <String>[];
    String current = '';
    for (final s in sentences) {
      if (current.length + s.length + 2 < 420) {
        current = current.isEmpty ? s : '$current. $s';
      } else {
        if (current.isNotEmpty) chunks.add(current);
        current = s;
      }
    }
    if (current.isNotEmpty) chunks.add(current);

    final results = <String>[];
    for (final chunk in chunks) {
      final uri = Uri.parse(
        'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(chunk)}&langpair=en|es',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final t = data['responseData']?['translatedText']?.toString();
        results.add(t ?? chunk);
      } else {
        results.add(chunk);
      }
    }
    return results.join('. ');
  }
}

class Apod {
  final String title;
  final String url;
  final String hdurl;
  final String videoUrl;
  final String explanation;
  final String mediaType;
  final String date;
  final String copyright;

  Apod({
    required this.title,
    required this.url,
    required this.hdurl,
    required this.videoUrl,
    required this.explanation,
    required this.mediaType,
    required this.date,
    required this.copyright,
  });

  static String _normalizeUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    return trimmed;
  }

  static String? _extractYouTubeId(String url) {
    final match = RegExp(
      r'(?:youtube\.com/(?:embed/|watch\?v=)|youtu\.be/)([A-Za-z0-9_-]{6,})',
    ).firstMatch(url);
    return match?.group(1);
  }

  static String _extractVideoUrl(Map<String, dynamic> j) {
    final html = (j['basic_html'] ?? '').toString();
    if (html.isNotEmpty) {
      final sourceMatch = RegExp(
        r'''<source[^>]+src=["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(html);
      if (sourceMatch != null) {
        return _normalizeUrl(sourceMatch.group(1)!);
      }

      final iframeMatch = RegExp(
        r'''<iframe[^>]+src=["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(html);
      if (iframeMatch != null) {
        final rawSrc = _normalizeUrl(iframeMatch.group(1)!);
        final ytId = _extractYouTubeId(rawSrc);
        if (ytId != null) {
          return 'https://www.youtube.com/watch?v=$ytId';
        }
        return rawSrc;
      }
    }

    final rawUrl = _normalizeUrl((j['url'] ?? '').toString());
    final ytId = _extractYouTubeId(rawUrl);
    if (ytId != null) {
      return 'https://www.youtube.com/watch?v=$ytId';
    }
    if (rawUrl.isNotEmpty) return rawUrl;
    return _normalizeUrl((j['permalink'] ?? '').toString());
  }

  factory Apod.fromJson(Map<String, dynamic> j) {
    final rawExplanation = (j['explanation'] ?? '').toString();
    final cleanExplanation = rawExplanation
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#039;', "'")
        .replaceAll('&quot;', '"')
        .trim();

    final rawCopyright = (j['copyright'] ?? j['credit'] ?? '').toString();
    final cleanCopyright = rawCopyright
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('\n', ' ')
        .trim();

    final mediaType = (j['media_type'] ?? 'image').toString();
    final videoUrl = mediaType == 'image' ? '' : _extractVideoUrl(j);

    String imageUrl = (j['hdurl'] ?? j['url'] ?? '').toString();
    if (imageUrl.contains('nasa-logo') && j['hdurl'] != null) {
      imageUrl = j['hdurl'].toString();
    }

    if (mediaType != 'image') {
      final hasThumbAsset = j['hdurl'] != null &&
          j['hdurl'].toString().isNotEmpty &&
          !j['hdurl'].toString().contains('nasa-logo');
      if (!hasThumbAsset) {
        final ytId = _extractYouTubeId(videoUrl);
        imageUrl =
            ytId != null ? 'https://img.youtube.com/vi/$ytId/hqdefault.jpg' : '';
      }
    }

    return Apod(
      title: (j['title'] ?? 'Sin título')
          .toString()
          .replaceAll('&#039;', "'")
          .replaceAll('&quot;', '"'),
      url: imageUrl,
      hdurl: (j['hdurl'] ?? imageUrl).toString(),
      videoUrl: videoUrl,
      explanation: cleanExplanation,
      mediaType: mediaType,
      date: j['date'] ?? '',
      copyright: cleanCopyright,
    );
  }
}

class ApodPage extends StatefulWidget {
  const ApodPage({super.key});

  @override
  State<ApodPage> createState() => _ApodPageState();
}

class _ApodPageState extends State<ApodPage> {
  static final DateTime _firstApodDate = DateTime(1995, 6, 16);

  late Future<Apod> _future;
  int _currentPage = 1; // 1 = Hoy, 2 = Ayer, 3 = Anteayer...
  int _totalPages = 11464; // Actualizado dinámicamente vía X-WP-TotalPages
  DateTime? _selectedDate; // No nulo cuando el usuario elige fecha en el calendario
  String _currentDateDisplay = '';

  // Estado de traducción
  bool _showSpanish = false;
  bool _isTranslating = false;
  final Map<String, String> _spanishExplanations = {};
  final Map<String, String> _spanishTitles = {};

  @override
  void initState() {
    super.initState();
    _future = fetchApod(page: _currentPage);
  }

  static String _formatYyyyMmDd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String _formatYyMmDd(DateTime d) {
    final y = (d.year % 100).toString().padLeft(2, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y$m$day';
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _isToday =>
      (_selectedDate == null && _currentPage == 1) ||
      (_selectedDate != null && _isSameDay(_selectedDate!, DateTime.now()));

  bool get _canGoPrevious => _selectedDate != null
      ? _selectedDate!.isAfter(_firstApodDate)
      : _currentPage < _totalPages;

  bool get _canGoNext {
    if (_selectedDate != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final current = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
      );
      return current.isBefore(today);
    }
    return _currentPage > 1;
  }

  // Consulta el endpoint actualizado de NASA (science.nasa.gov) con fallback
  Future<Apod> fetchApod({int page = 1, DateTime? date}) async {
    if (date != null) {
      final yymmdd = _formatYyMmDd(date);
      final yyyymmdd = _formatYyyyMmDd(date);
      try {
        final res = await http
            .get(
              Uri.parse(
                'https://science.nasa.gov/wp-json/wp/v2/apod-basic/$yymmdd',
              ),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) {
            final apod = Apod.fromJson(decoded);
            if (mounted) _currentDateDisplay = apod.date;
            return apod;
          }
        }
      } catch (e) {
        debugPrint('Error en consulta por fecha ($yyyymmdd): $e');
      }

      // Fallback por fecha: api.nasa.gov
      try {
        final resFallback = await http
            .get(
              Uri.parse(
                'https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY&date=$yyyymmdd',
              ),
            )
            .timeout(const Duration(seconds: 10));
        if (resFallback.statusCode == 200) {
          final apod = Apod.fromJson(jsonDecode(resFallback.body));
          if (mounted) _currentDateDisplay = apod.date;
          return apod;
        }
      } catch (e) {
        debugPrint('Error en fallback por fecha: $e');
      }

      throw Exception('No hay publicación registrada para el $yyyymmdd');
    }

    try {
      final res = await http
          .get(
            Uri.parse(
              'https://science.nasa.gov/wp-json/wp/v2/apod-basic?per_page=1&page=$page',
            ),
          )
          .timeout(const Duration(seconds: 10));

      final totalPagesHeader = int.tryParse(res.headers['x-wp-totalpages'] ?? '');
      if (totalPagesHeader != null && totalPagesHeader > 0) {
        _totalPages = totalPagesHeader;
      }

      if (res.statusCode == 200) {
        final list = jsonDecode(res.body);
        if (list is List && list.isNotEmpty) {
          final apod = Apod.fromJson(list[0]);
          if (mounted) _currentDateDisplay = apod.date;
          return apod;
        }
      }
    } catch (e) {
      debugPrint('Error en endpoint principal: $e. Intentando fallback...');
    }

    // Fallback: api.nasa.gov (con fecha aproximada si page > 1)
    final fallbackDate = DateTime.now().subtract(Duration(days: page - 1));
    final dateQuery = page > 1 ? '&date=${_formatYyyyMmDd(fallbackDate)}' : '';
    final resFallback = await http
        .get(
          Uri.parse(
            'https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY$dateQuery',
          ),
        )
        .timeout(const Duration(seconds: 10));

    if (resFallback.statusCode == 200) {
      return Apod.fromJson(jsonDecode(resFallback.body));
    }

    throw Exception('Error al conectar con los servidores de la NASA');
  }

  void _loadPage(int page) {
    if (page < 1 || page > _totalPages) return;
    setState(() {
      _selectedDate = null;
      _currentPage = page;
      _showSpanish = false; // Resetear vista al idioma original
      _future = fetchApod(page: page);
    });
  }

  void _loadDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (normalized.isBefore(_firstApodDate) || normalized.isAfter(today)) return;

    setState(() {
      _selectedDate = normalized;
      _showSpanish = false;
      _future = fetchApod(date: normalized);
    });
  }

  void _reloadCurrent() {
    if (_selectedDate != null) {
      _loadDate(_selectedDate!);
    } else {
      _loadPage(_currentPage);
    }
  }

  void _goPrevious() {
    if (_selectedDate != null) {
      final prev = _selectedDate!.subtract(const Duration(days: 1));
      if (!prev.isBefore(_firstApodDate)) _loadDate(prev);
    } else {
      _loadPage(_currentPage + 1);
    }
  }

  void _goNext() {
    if (_selectedDate != null) {
      final next = _selectedDate!.add(const Duration(days: 1));
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (!next.isAfter(today)) _loadDate(next);
    } else if (_currentPage > 1) {
      _loadPage(_currentPage - 1);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime initial =
        _selectedDate ?? DateTime.tryParse(_currentDateDisplay) ?? today;
    if (initial.isBefore(_firstApodDate)) initial = _firstApodDate;
    if (initial.isAfter(today)) initial = today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _firstApodDate,
      lastDate: today,
      helpText: 'Selecciona una fecha del cosmos',
      cancelText: 'Cancelar',
      confirmText: 'Ver fecha',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6366F1),
              onPrimary: Colors.white,
              surface: Color(0xFF131B2E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      _loadDate(picked);
    }
  }

  void _randomPhoto() {
    final randomPage = Random().nextInt(_totalPages) + 1;
    _loadPage(randomPage);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.rocket_launch, color: Colors.amberAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Viajando en el archivo cósmico (#$randomPage de $_totalPages) 🚀',
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1E293B),
      ),
    );
  }

  Future<void> _openVideo(Apod apod) async {
    final raw = apod.videoUrl.isNotEmpty ? apod.videoUrl : apod.url;
    final uri = Uri.tryParse(raw);
    if (uri == null || raw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enlace de video no disponible')),
      );
      return;
    }

    var launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E293B),
          content: Text('No se pudo abrir el reproductor: $raw'),
        ),
      );
    }
  }

  Future<void> _toggleTranslation(Apod apod) async {
    if (_showSpanish) {
      // Regresar al inglés
      setState(() {
        _showSpanish = false;
      });
      return;
    }

    // Si ya fue traducida esta foto, mostrar de inmediato
    if (_spanishExplanations.containsKey(apod.explanation)) {
      setState(() {
        _showSpanish = true;
      });
      return;
    }

    setState(() {
      _isTranslating = true;
    });

    try {
      // Traducir simultáneamente título y explicación para una experiencia completa
      final results = await Future.wait([
        TranslationService.translateToSpanish(apod.title),
        TranslationService.translateToSpanish(apod.explanation),
      ]);

      if (mounted) {
        setState(() {
          _spanishTitles[apod.title] = results[0];
          _spanishExplanations[apod.explanation] = results[1];
          _showSpanish = true;
          _isTranslating = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF34D399), size: 20),
                SizedBox(width: 10),
                Text('Traducido exitosamente al español'),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF1E293B),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTranslating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Error al traducir: $e')),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF1E293B),
          ),
        );
      }
    }
  }

  void _openImageZoom(BuildContext context, Apod apod) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(8),
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    apod.hdurl.isNotEmpty ? apod.hdurl : apod.url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF6366F1),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                  ),
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Positioned(
                bottom: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pinch, color: Colors.white70, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Pellizca para hacer zoom en HD',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Text(
                'NASA',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Foto Astronómica',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded,
                color: Color(0xFF818CF8)),
            tooltip: 'Elegir fecha',
            onPressed: _pickDate,
          ),
          IconButton(
            icon: const Icon(Icons.casino_outlined, color: Colors.amberAccent),
            tooltip: 'Fecha Aleatoria',
            onPressed: _randomPhoto,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Recargar',
            onPressed: _reloadCurrent,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF090D16),
              Color(0xFF0F172A),
              Color(0xFF090D16),
            ],
          ),
        ),
        child: FutureBuilder<Apod>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6366F1)
                                    .withValues(alpha: 0.25),
                                blurRadius: 20,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            strokeWidth: 3.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF6366F1),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.rocket_launch,
                          size: 20,
                          color: Color(0xFF818CF8),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Explorando el cosmos...',
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Descargando fotografía de la NASA',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            }

            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Card(
                    color: const Color(0xFF131B2E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: Colors.redAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.satellite_alt_outlined,
                              color: Colors.redAccent,
                              size: 42,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Error al obtener la imagen',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${snap.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _reloadCurrent,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Reintentar conexión'),
                              ),
                              if (!_isToday)
                                OutlinedButton.icon(
                                  onPressed: () => _loadPage(1),
                                  icon: const Icon(Icons.today_rounded),
                                  label: const Text('Ir a hoy'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            final a = snap.data!;
            final displayTitle = _showSpanish && _spanishTitles.containsKey(a.title)
                ? _spanishTitles[a.title]!
                : a.title;
            final displayExplanation = _showSpanish &&
                    _spanishExplanations.containsKey(a.explanation)
                ? _spanishExplanations[a.explanation]!
                : a.explanation;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Barra de Navegación de Fechas estilo Glassmorphism
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131B2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _canGoPrevious ? _goPrevious : null,
                          icon: const Icon(Icons.chevron_left_rounded, size: 18),
                          label: const Text('Anterior'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white24,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            side: BorderSide(
                              color: _canGoPrevious
                                  ? Colors.white.withValues(alpha: 0.16)
                                  : Colors.white10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(10),
                            child: Tooltip(
                              message: 'Toca para elegir una fecha en el calendario',
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1)
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF6366F1)
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.calendar_today_rounded,
                                      size: 13,
                                      color: Color(0xFF818CF8),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      a.date.isNotEmpty
                                          ? a.date
                                          : _currentDateDisplay,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFC7D2FE),
                                        fontSize: 13,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    if (_isToday) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF22C55E)
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'HOY',
                                          style: TextStyle(
                                            color: Color(0xFF4ADE80),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(width: 2),
                                      const Icon(
                                        Icons.arrow_drop_down_rounded,
                                        size: 16,
                                        color: Color(0xFF818CF8),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _canGoNext ? _goNext : null,
                          icon: const Icon(Icons.chevron_right_rounded, size: 18),
                          label: const Text('Siguiente'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white24,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            side: BorderSide(
                              color: _canGoNext
                                  ? Colors.white.withValues(alpha: 0.16)
                                  : Colors.white10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Tarjeta Visual (Imagen con zoom o Video)
                  if (a.mediaType == 'image')
                    GestureDetector(
                      onTap: () => _openImageZoom(context, a),
                      child: Hero(
                        tag: 'apod_image_${a.date}',
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              children: [
                                Image.network(
                                  a.url,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return Container(
                                      height: 300,
                                      color: const Color(0xFF131B2E),
                                      alignment: Alignment.center,
                                      child: CircularProgressIndicator(
                                        value: progress.expectedTotalBytes != null
                                            ? progress.cumulativeBytesLoaded /
                                                progress.expectedTotalBytes!
                                            : null,
                                        color: const Color(0xFF6366F1),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                    height: 240,
                                    color: const Color(0xFF131B2E),
                                    alignment: Alignment.center,
                                    child: const Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.broken_image_rounded,
                                            size: 48, color: Colors.grey),
                                        SizedBox(height: 8),
                                        Text('No se pudo cargar la imagen'),
                                      ],
                                    ),
                                  ),
                                ),
                                // Badge flotante de HD / Foto APOD
                                Positioned(
                                  top: 12,
                                  left: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: 0.15),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.auto_awesome,
                                            size: 13, color: Colors.amberAccent),
                                        SizedBox(width: 5),
                                        Text(
                                          'APOD HD',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Indicador de Zoom
                                Positioned(
                                  bottom: 12,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: 0.15),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.fullscreen_rounded,
                                            size: 14, color: Colors.white70),
                                        SizedBox(width: 4),
                                        Text(
                                          'Toca para ampliar',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    InAppVideoPlayerCard(
                      key: ValueKey('${a.date}_${a.videoUrl}'),
                      apod: a,
                      onOpenExternal: () => _openVideo(a),
                    ),

                  const SizedBox(height: 12),

                  // Metadata chips (Créditos y tipo de medio)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (a.copyright.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copyright_rounded,
                                  size: 13, color: Colors.grey.shade400),
                              const SizedBox(width: 5),
                              Text(
                                a.copyright,
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              a.mediaType == 'image'
                                  ? Icons.image_outlined
                                  : Icons.movie_outlined,
                              size: 13,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              a.mediaType == 'image' ? 'Fotografía' : 'Video',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Título Principal
                  Text(
                    displayTitle,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      height: 1.25,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Tarjeta de Explicación con Botón de Traducción Profesional
                  Card(
                    color: const Color(0xFF131B2E),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: _showSpanish
                            ? const Color(0xFF6366F1).withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Cabecera de la sección con Botón de Traducción y Copiado
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.menu_book_rounded,
                                  size: 18,
                                  color: Color(0xFF818CF8),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Explicación',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),

                              // Botón de Traducción Rápida
                              FilledButton.tonalIcon(
                                onPressed: _isTranslating
                                    ? null
                                    : () => _toggleTranslation(a),
                                icon: _isTranslating
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        _showSpanish
                                            ? Icons.translate_rounded
                                            : Icons.g_translate_rounded,
                                        size: 16,
                                      ),
                                label: Text(
                                  _isTranslating
                                      ? 'Traduciendo...'
                                      : (_showSpanish
                                          ? 'Original (EN)'
                                          : 'Traducir a Español'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _showSpanish
                                      ? const Color(0xFF6366F1)
                                      : const Color(0xFF1E293B),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                      color: _showSpanish
                                          ? const Color(0xFF818CF8)
                                          : Colors.white
                                              .withValues(alpha: 0.15),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(width: 4),

                              // Botón para copiar texto
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                tooltip: 'Copiar explicación',
                                color: Colors.grey.shade400,
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: displayExplanation),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      content: const Text(
                                        'Texto copiado al portapapeles 📋',
                                      ),
                                      duration: const Duration(seconds: 2),
                                      backgroundColor: const Color(0xFF1E293B),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),

                          // Indicador si está en modo español
                          if (_showSpanish) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome,
                                      size: 13, color: Color(0xFF818CF8)),
                                  SizedBox(width: 6),
                                  Text(
                                    'Traducción automática (EN ➔ ES)',
                                    style: TextStyle(
                                      color: Color(0xFFC7D2FE),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 14),

                          // Contenido del texto
                          SelectableText(
                            displayExplanation,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.65,
                              letterSpacing: 0.2,
                              color: Colors.grey.shade200,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _randomPhoto,
          backgroundColor: const Color(0xFF6366F1),
          foregroundColor: Colors.white,
          elevation: 0,
          highlightElevation: 0,
          icon: const Icon(Icons.rocket_launch_rounded, size: 20),
          label: const Text(
            'Explorar Cosmos 🎲',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
      ),
    );
  }
}


/// Reproductor de video integrado en la tarjeta (soporta MP4 directos y YouTube).
class InAppVideoPlayerCard extends StatefulWidget {
  final Apod apod;
  final VoidCallback onOpenExternal;

  const InAppVideoPlayerCard({
    super.key,
    required this.apod,
    required this.onOpenExternal,
  });

  @override
  State<InAppVideoPlayerCard> createState() => _InAppVideoPlayerCardState();
}

class _InAppVideoPlayerCardState extends State<InAppVideoPlayerCard> {
  VideoPlayerController? _controller;
  bool _isLoading = false;
  bool _isMuted = false;
  String? _errorMessage;
  String? _webYouTubeId;

  @override
  void didUpdateWidget(covariant InAppVideoPlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apod.date != widget.apod.date ||
        oldWidget.apod.videoUrl != widget.apod.videoUrl) {
      _webYouTubeId = null;
      _errorMessage = null;
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerTick);
    _controller?.dispose();
    super.dispose();
  }

  void _onControllerTick() {
    if (mounted) setState(() {});
  }

  Future<Uri> _resolvePlayableUri(String rawUrl) async {
    final ytId = Apod._extractYouTubeId(rawUrl);
    if (ytId != null) {
      final yt = YoutubeExplode();
      try {
        final manifest = await yt.videos.streamsClient.getManifest(ytId);
        if (manifest.muxed.isNotEmpty) {
          return manifest.muxed.withHighestBitrate().url;
        }
        if (manifest.hls.isNotEmpty) {
          return manifest.hls.first.url;
        }
        throw Exception('No se encontró flujo reproducible para este video');
      } finally {
        yt.close();
      }
    }
    return Uri.parse(rawUrl);
  }

  Future<void> _startPlayback() async {
    final raw = widget.apod.videoUrl.isNotEmpty
        ? widget.apod.videoUrl
        : widget.apod.url;
    if (raw.isEmpty) {
      setState(() => _errorMessage = 'Enlace de video no disponible');
      return;
    }

    if (kIsWeb) {
      final ytId = Apod._extractYouTubeId(raw);
      if (ytId != null) {
        setState(() {
          _webYouTubeId = ytId;
          _isLoading = false;
          _errorMessage = null;
        });
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final playableUri = await _resolvePlayableUri(raw);
      final controller = VideoPlayerController.networkUrl(playableUri);
      await controller.initialize();
      await controller.setLooping(false);
      await controller.play();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      controller.addListener(_onControllerTick);
      setState(() {
        _controller = controller;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error reproduciendo video in-app: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No se pudo cargar el video dentro de la app.';
        });
      }
    }
  }

  Future<void> _togglePlayPause() async {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  Future<void> _toggleMute() async {
    final c = _controller;
    if (c == null) return;
    final nextMuted = !_isMuted;
    await c.setVolume(nextMuted ? 0.0 : 1.0);
    if (mounted) {
      setState(() => _isMuted = nextMuted);
    }
  }

  void _openFullscreen() {
    final c = _controller;
    if (c == null) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: c.value.aspectRatio > 0
                        ? c.value.aspectRatio
                        : 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          GestureDetector(
                            onTap: () async {
                              await _togglePlayPause();
                              setModalState(() {});
                            },
                            child: VideoPlayer(c),
                          ),
                          VideoProgressIndicator(
                            c,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: Color(0xFF6366F1),
                              bufferedColor: Colors.white30,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.65),
                      ),
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$mins:$secs';
    }
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && _webYouTubeId != null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: WebYouTubeEmbed(videoId: _webYouTubeId!),
          ),
        ),
      );
    }

    final controller = _controller;

    if (controller != null && controller.value.isInitialized) {
      final ratio = controller.value.aspectRatio > 0
          ? controller.value.aspectRatio
          : 16 / 9;
      return Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: ratio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      onTap: _togglePlayPause,
                      child: VideoPlayer(controller),
                    ),
                    if (!controller.value.isPlaying)
                      GestureDetector(
                        onTap: _togglePlayPause,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.88),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                      ),
                    if (controller.value.isBuffering)
                      const CircularProgressIndicator(
                        color: Color(0xFF6366F1),
                      ),
                  ],
                ),
              ),
              Container(
                color: const Color(0xFF131B2E),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFF6366F1),
                        bufferedColor: Colors.white24,
                        backgroundColor: Colors.white10,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: _togglePlayPause,
                          icon: Icon(
                            controller.value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: _toggleMute,
                          icon: Icon(
                            _isMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                        ),
                        Text(
                          '${_formatDuration(controller.value.position)} / ${_formatDuration(controller.value.duration)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Abrir externamente',
                          onPressed: widget.onOpenExternal,
                          icon: const Icon(
                            Icons.open_in_new_rounded,
                            color: Colors.white60,
                            size: 18,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Pantalla completa',
                          onPressed: _openFullscreen,
                          icon: const Icon(
                            Icons.fullscreen_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _isLoading ? null : _startPlayback,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.apod.url.isNotEmpty)
                Image.network(
                  widget.apod.url,
                  height: 250,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    height: 250,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF131B2E), Color(0xFF1E1B4B)],
                      ),
                    ),
                  ),
                )
              else
                Container(
                  height: 250,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF131B2E), Color(0xFF1E1B4B)],
                    ),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        Colors.black.withValues(alpha: 0.62),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isLoading)
                const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF6366F1)),
                    SizedBox(height: 12),
                    Text(
                      'Cargando video...',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              else if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.amberAccent, size: 36),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _startPlayback,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Reintentar'),
                          ),
                          OutlinedButton.icon(
                            onPressed: widget.onOpenExternal,
                            icon:
                                const Icon(Icons.open_in_new_rounded, size: 16),
                            label: const Text('Abrir en navegador'),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.92),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.5),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_rounded,
                          size: 14, color: Colors.amberAccent),
                      SizedBox(width: 5),
                      Text(
                        'VIDEO APOD',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!_isLoading && _errorMessage == null)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_outline_rounded,
                            size: 14, color: Colors.white70),
                        SizedBox(width: 5),
                        Text(
                          'Reproducir aquí',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
