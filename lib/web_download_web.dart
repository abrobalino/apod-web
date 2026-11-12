import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

void triggerWebDownload(Uint8List bytes, String filename, String mimeType) {
  final jsBytes = bytes.toJS;
  final parts = [jsBytes].toJS;
  final options = JSObject();
  options['type'] = mimeType.toJS;

  final blobCtor = globalContext['Blob'] as JSFunction;
  final blob = blobCtor.callAsConstructor<JSObject>(parts, options);

  final urlApi = globalContext['URL'] as JSObject;
  final objectUrl = urlApi.callMethod<JSString>('createObjectURL'.toJS, blob);

  final document = globalContext['document'] as JSObject;
  final anchor = document.callMethod<JSObject>('createElement'.toJS, 'a'.toJS);
  anchor['href'] = objectUrl;
  anchor['download'] = filename.toJS;
  anchor.callMethod<JSAny?>('click'.toJS);

  urlApi.callMethod<JSAny?>('revokeObjectURL'.toJS, objectUrl);
}

