import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';

import '../legal/legal_documents.dart';

/// 개인정보처리방침이나 이용약관을 보여준다.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(document.assetPath),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('문서를 불러오지 못했어요.'));
          }
          final text = snapshot.data;
          if (text == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return SelectionArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                for (final line in _lines(text)) _render(context, line),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 빈 줄은 건너뛴다. 첫 제목은 앱바와 겹쳐서 뺀다.
  static Iterable<String> _lines(String markdown) => markdown
      .split('\n')
      .map((l) => l.trimRight())
      .where((l) => l.isNotEmpty && !l.startsWith('# '));

  /// 이 문서들에 쓰는 마크다운(제목, 목록, 문단)만 간단히 그린다.
  static Widget _render(BuildContext context, String line) {
    final theme = Theme.of(context).textTheme;
    if (line.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(line.substring(3), style: theme.titleMedium),
      );
    }
    if (line.startsWith('- ')) {
      return Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 6),
        child: Text('•  ${line.substring(2)}'),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(line),
    );
  }
}
