import 'dart:io';

void main() async {
  final file = File('lib/reader_page.dart');
  String content = await file.readAsString();

  content = content.replaceAll('â”€â”€', '──');
  content = content.replaceAll('â€”', '—');
  content = content.replaceAll('ðŸŒ ', '🌐');
  content = content.replaceAll('â “', '❓');
  content = content.replaceAll('â ¸', '⏸');
  content = content.replaceAll('â ©', '⏭');
  content = content.replaceAll('â ª', '⏮');
  content = content.replaceAll('âˆ’', '−');
  content = content.replaceAll('âš¡', '⚡');
  content = content.replaceAll('ðŸ ¢', '🐢');
  content = content.replaceAll('ðŸ”„', '🔄');
  content = content.replaceAll('ðŸ›‘', '🛑');
  content = content.replaceAll('ðŸ”†', '🖍️');

  content = content.replaceAll('ðŸ‡ºðŸ‡¸', '🇺🇸');
  content = content.replaceAll('ðŸ‡ªðŸ‡¸', '🇪🇸');
  content = content.replaceAll('ðŸ‡«ðŸ‡·', '🇫🇷');
  content = content.replaceAll('ðŸ‡¸ðŸ‡¦', '🇸🇦');
  content = content.replaceAll('ðŸ‡¹ðŸ‡·', '🇹🇷');
  content = content.replaceAll('ðŸ‡¨ðŸ‡³', '🇨🇳');
  content = content.replaceAll('ðŸŒ ', '🌐');

  await file.writeAsString(content);
  print('Fixed unicode in reader_page.dart');
}
