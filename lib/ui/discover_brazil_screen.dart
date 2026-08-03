import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/brazil_catalog.dart';
import '../domain/catalog_book.dart';

class DiscoverBrazilScreen extends StatefulWidget {
  const DiscoverBrazilScreen({super.key});

  @override
  State<DiscoverBrazilScreen> createState() => _DiscoverBrazilScreenState();
}

class _DiscoverBrazilScreenState extends State<DiscoverBrazilScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openBook(CatalogBook book) async {
    final opened = await launchUrl(
      book.pageUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir a página do livro.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = brazilCatalog.where((book) => book.matches(_query)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Descobrir no Brasil')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Buscar título, autor ou categoria',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar busca',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Catálogo inicial do BaixeLivros. O download é concluído no navegador e depois pode ser importado para a biblioteca.',
            ),
          ),
          Expanded(
            child: books.isEmpty
                ? const Center(child: Text('Nenhum livro encontrado.'))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: books.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return ListTile(
                        leading: const Icon(Icons.menu_book_outlined, size: 34),
                        title: Text(book.title),
                        subtitle: Text(
                          '${book.author}\n${book.category} · ${book.format} · ${book.license}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => _openBook(book),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
