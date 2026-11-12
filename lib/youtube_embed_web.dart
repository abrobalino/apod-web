import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/widgets.dart';

class WebYouTubeEmbed extends StatelessWidget {
  final String videoId;

  const WebYouTubeEmbed({super.key, required this.videoId});

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      key: ValueKey(videoId),
      tagName: 'iframe',
      onElementCreated: (Object element) {
        final iframe = element as JSObject;
        iframe['src'] =
            'https://www.youtube.com/embed/$videoId?autoplay=1&rel=0'.toJS;
        iframe['allow'] =
            'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share'
                .toJS;
        iframe['allowFullscreen'] = true.toJS;
        final style = iframe['style'] as JSObject;
        style['border'] = 'none'.toJS;
        style['width'] = '100%'.toJS;
        style['height'] = '100%'.toJS;
      },
    );
  }
}

