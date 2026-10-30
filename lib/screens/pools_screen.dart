import 'package:flutter/material.dart';

import '../data.dart';
import '../models.dart';
import 'pool_screen.dart';

class PoolsScreen extends StatefulWidget {
  const PoolsScreen({super.key});

  @override
  State<PoolsScreen> createState() => _PoolsScreenState();
}

class _PoolsScreenState extends State<PoolsScreen> {
  late Future<List<Pool>> _future;

  @override
  void initState() {
    super.initState();
    _future = Repo.myPools();
  }

  void _reload() => setState(() => _future = Repo.myPools());

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _create() async {
    final res = await showDialog<_PoolForm>(
      context: context,
      builder: (_) => const _PoolFormDialog(
        title: 'Aile havuzu oluştur',
        askName: true,
        defaultRole: 'Aile Reisi',
        action: 'Oluştur',
      ),
    );
    if (res == null) return;
    try {
      await Repo.createPool(res.name, res.role, familyRoles[res.role] ?? '👥');
      _reload();
    } catch (e) {
      _toast(e.toString().contains('pool_limit_reached')
          ? 'En fazla 3 havuz oluşturabilirsiniz.'
          : 'Havuz oluşturulamadı.');
    }
  }

  Future<void> _join() async {
    final res = await showDialog<_PoolForm>(
      context: context,
      builder: (_) => const _PoolFormDialog(
        title: 'Koda göre katıl',
        askCode: true,
        defaultRole: 'Aile Ferdi',
        action: 'İstek gönder',
      ),
    );
    if (res == null) return;
    try {
      final ok =
          await Repo.requestJoin(res.code, res.role, familyRoles[res.role] ?? '👥');
      _toast(ok
          ? 'İstek gönderildi. Havuz yöneticisinin onayını bekleyin.'
          : 'Kod geçersiz.');
    } catch (e) {
      final s = e.toString();
      if (s.contains('already_member')) {
        _toast('Zaten bu havuzun üyesisiniz.');
      } else if (s.contains('too_many_attempts')) {
        _toast('Çok fazla deneme yaptınız. Daha sonra tekrar deneyin.');
      } else {
        _toast('İstek gönderilemedi.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aile Havuzlarım'),
        actions: [
          IconButton(
            tooltip: 'Çıkış yap',
            icon: const Icon(Icons.logout),
            onPressed: () => supa.auth.signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<Pool>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: const [
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Havuzlar yüklenemedi. Aşağı çekerek yenileyin.'),
                ),
              ]);
            }
            final pools = snap.data ?? [];
            if (pools.isEmpty) {
              return ListView(children: const [
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Henüz bir havuzunuz yok.\nYeni bir aile havuzu oluşturun '
                    'veya size verilen kodla katılın.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ]);
            }
            return ListView(
              children: [
                for (final p in pools)
                  ListTile(
                    leading: Text(p.ownerId == myId ? '👑' : '👨‍👩‍👧',
                        style: const TextStyle(fontSize: 28)),
                    title: Text(p.name),
                    subtitle: Text(p.ownerId == myId ? 'Yöneticisiniz' : 'Üyesiniz'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => PoolScreen(pool: p)),
                      );
                      _reload();
                    },
                  ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'join',
            onPressed: _join,
            icon: const Icon(Icons.key),
            label: const Text('Koda katıl'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'create',
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: const Text('Havuz oluştur'),
          ),
        ],
      ),
    );
  }
}

class _PoolForm {
  final String name;
  final String code;
  final String role;
  _PoolForm(this.name, this.code, this.role);
}

class _PoolFormDialog extends StatefulWidget {
  final String title;
  final String action;
  final String defaultRole;
  final bool askName;
  final bool askCode;

  const _PoolFormDialog({
    required this.title,
    required this.action,
    required this.defaultRole,
    this.askName = false,
    this.askCode = false,
  });

  @override
  State<_PoolFormDialog> createState() => _PoolFormDialogState();
}

class _PoolFormDialogState extends State<_PoolFormDialog> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  late String _role = widget.defaultRole;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.askName)
              TextField(
                controller: _name,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Havuz adı (örn. Yılmaz Ailesi)'),
              ),
            if (widget.askCode)
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Davet kodu (ABCD-EFGH)'),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _role,
              decoration: const InputDecoration(labelText: 'Havuzdaki rolünüz'),
              items: [
                for (final e in familyRoles.entries)
                  DropdownMenuItem(value: e.key, child: Text('${e.value}  ${e.key}')),
              ],
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final code = _code.text.trim();
            if (widget.askName && name.isEmpty) return;
            if (widget.askCode && code.isEmpty) return;
            Navigator.pop(context, _PoolForm(name, code, _role));
          },
          child: Text(widget.action),
        ),
      ],
    );
  }
}
