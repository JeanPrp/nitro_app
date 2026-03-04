import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const NitroApp());
}

/// =========================================================
///  NITRO STAFF — Firebase Ready (1 arquivo)
///  - Auth email/senha
///  - Role (seller/ops) em users/{uid}
///  - Clients em clients (agora mais completo)
///  - Appointments em appointments (agora com valor, KM, checklist)
/// =========================================================

class NitroApp extends StatelessWidget {
  const NitroApp({super.key});

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF070B12);
    const accent = Color(0xFF3AA0FF);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nitro Staff',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorSchemeSeed: accent,
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0F1724).withOpacity(0.92),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: accent.withOpacity(0.9), width: 1.3),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// =========================================================
///  Firestore schema (coleções) — atualizado
///
///  users/{uid}: { name, role: "seller"|"ops", createdAt }
///
///  clients/{id}:
///   { fullName, phone, car, plate, color, km, notes, createdBy, createdAt }
///
///  appointments/{id}:
///   {
///     clientId, service, scheduledAt, notes,
///     price, kmIn, kmOut,
///     checkInAt, checkOutAt,
///     postChecklist (map),
///     status, operatorId, operatorName,
///     startedAt, finishedAt, workedSeconds,
///     createdBy, createdAt
///   }
/// =========================================================

enum Role { seller, ops }
enum ApptStatus { scheduled, inProgress, done, canceled }

Role roleFromString(String s) => s == 'ops' ? Role.ops : Role.seller;
String roleToString(Role r) => r == Role.ops ? 'ops' : 'seller';

ApptStatus statusFromString(String s) {
  switch (s) {
    case 'inProgress':
      return ApptStatus.inProgress;
    case 'done':
      return ApptStatus.done;
    case 'canceled':
      return ApptStatus.canceled;
    default:
      return ApptStatus.scheduled;
  }
}

String statusToString(ApptStatus s) {
  switch (s) {
    case ApptStatus.inProgress:
      return 'inProgress';
    case ApptStatus.done:
      return 'done';
    case ApptStatus.canceled:
      return 'canceled';
    case ApptStatus.scheduled:
      return 'scheduled';
  }
}

String two(int n) => n.toString().padLeft(2, '0');
String fmtDate(DateTime dt) => '${two(dt.day)}/${two(dt.month)}/${dt.year}';
String fmtTime(DateTime dt) => '${two(dt.hour)}:${two(dt.minute)}';
String fmtDateTime(DateTime dt) => '${fmtDate(dt)} • ${fmtTime(dt)}';
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int asInt(dynamic v, {int def = 0}) {
  if (v == null) return def;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? def;
}

/// =========================================================
///  Checklist final (pós-serviço)
/// =========================================================

const postChecklistItems = <String, String>{
  'wheels_ok': 'Rodas limpas',
  'paint_ok': 'Pintura sem marcas/manchas',
  'glass_ok': 'Vidros limpos',
  'interior_ok': 'Interior aspirado',
  'dash_ok': 'Painel/console/volante limpos',
  'mats_ok': 'Tapetes limpos e reposicionados',
  'tires_ok': 'Pretinho aplicado',
  'no_drips': 'Sem escorridos de água',
  'belongings': 'Pertences devolvidos',
  'evo_mats': 'Tapetes EVA posicionados',
  'steering_tape': 'Fita no volante colocada',
};

/// =========================================================
///  Firebase helpers
/// =========================================================

final _auth = FirebaseAuth.instance;
final _db = FirebaseFirestore.instance;

User? get currentUser => _auth.currentUser;

DocumentReference<Map<String, dynamic>> userDoc(String uid) => _db.collection('users').doc(uid);
CollectionReference<Map<String, dynamic>> clientsCol() => _db.collection('clients');
CollectionReference<Map<String, dynamic>> apptsCol() => _db.collection('appointments');

Future<void> ensureUserDoc({required String uid, required String name, required Role role}) async {
  final ref = userDoc(uid);
  final snap = await ref.get();
  if (!snap.exists) {
    await ref.set({
      'name': name,
      'role': roleToString(role),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

/// =========================================================
///  AUTH GATE
/// =========================================================

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data;
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _LoadingPage(text: 'Conectando...');
        }
        if (user == null) return const LoginPage();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: userDoc(user.uid).snapshots(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const _LoadingPage(text: 'Carregando perfil...');
            }

            final doc = userSnap.data;
            if (doc == null || !doc.exists) {
              // primeiro login: pedir nome e role
              return const RoleSetupPage();
            }

            final data = doc.data() ?? {};
            final role = roleFromString((data['role'] ?? 'seller').toString());
            if (role == Role.seller) return const SellerShell();
            return const OpsShell();
          },
        );
      },
    );
  }
}

class _LoadingPage extends StatelessWidget {
  final String text;
  const _LoadingPage({required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(text, style: TextStyle(color: Colors.white.withOpacity(0.75))),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================
///  LOGIN + CADASTRO (email/senha)
/// =========================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool isLogin = true;
  bool loading = false;

  final email = TextEditingController();
  final pass = TextEditingController();

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final e = email.text.trim();
    final p = pass.text.trim();

    if (!e.contains('@') || p.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email inválido ou senha muito curta (mín 6).')),
      );
      return;
    }

    setState(() => loading = true);
    try {
      if (isLogin) {
        await _auth.signInWithEmailAndPassword(email: e, password: p);
      } else {
        await _auth.createUserWithEmailAndPassword(email: e, password: p);
      }
    } on FirebaseAuthException catch (ex) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ex.message ?? 'Erro no login/cadastro')),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          children: [
            const TopHeader(
              title: 'Nitro Staff',
              subtitle: 'Login real (Firebase) • Email & senha',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    selected: isLogin,
                    label: const Text('Entrar'),
                    onSelected: (_) => setState(() => isLogin = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChoiceChip(
                    selected: !isLogin,
                    label: const Text('Criar conta'),
                    onSelected: (_) => setState(() => isLogin = false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha (mín 6)', prefixIcon: Icon(Icons.lock)),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: loading ? null : submit,
                icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator()) : const Icon(Icons.login),
                label: Text(isLogin ? 'Entrar' : 'Criar conta'),
              ),
            ),
            const SizedBox(height: 10),
            Text('', style: TextStyle(color: Colors.white.withOpacity(0.65))),
          ],
        ),
      ),
    );
  }
}

/// =========================================================
///  PRIMEIRO ACESSO: definir Nome + Perfil
/// =========================================================

class RoleSetupPage extends StatefulWidget {
  const RoleSetupPage({super.key});

  @override
  State<RoleSetupPage> createState() => _RoleSetupPageState();
}

class _RoleSetupPageState extends State<RoleSetupPage> {
  final name = TextEditingController();
  Role role = Role.seller;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final u = currentUser;
    if (u == null) return;

    final n = name.text.trim();
    if (n.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Digite seu nome.')));
      return;
    }

    setState(() => saving = true);
    try {
      await ensureUserDoc(uid: u.uid, name: n, role: role);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro salvando perfil: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          children: [
            const TopHeader(title: 'Primeiro acesso', subtitle: 'Defina seu nome e perfil'),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Seu nome', prefixIcon: Icon(Icons.badge)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    selected: role == Role.seller,
                    label: const Text('Vendedor'),
                    onSelected: (_) => setState(() => role = Role.seller),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChoiceChip(
                    selected: role == Role.ops,
                    label: const Text('Operacional'),
                    onSelected: (_) => setState(() => role = Role.ops),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: saving ? null : save,
                icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator()) : const Icon(Icons.check),
                label: const Text('Salvar e continuar'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Depois a gente trava isso por regra (somente admin define perfil).',
              style: TextStyle(color: Colors.white.withOpacity(0.65)),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================
///  UI base
/// =========================================================

class TopHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const TopHeader({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF3AA0FF);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(0.18),
            const Color(0xFF0F1724).withOpacity(0.85),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withOpacity(0.22)),
            ),
            child: const Icon(Icons.bolt, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900));
}

class NitroTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const NitroTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF3AA0FF);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF0F1724).withOpacity(0.92),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: accent.withOpacity(0.12),
                border: Border.all(color: accent.withOpacity(0.18)),
              ),
              child: Icon(icon, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.65))),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class GlassBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;

  const GlassBottomNav({super.key, required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF3AA0FF);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF0F1724).withOpacity(0.62),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                blurRadius: 28,
                offset: const Offset(0, 12),
                color: Colors.black.withOpacity(0.35),
              ),
            ],
          ),
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, c) {
              final seg = c.maxWidth / items.length;

              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    left: seg * index,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: seg,
                      padding: const EdgeInsets.all(6),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(colors: [accent.withOpacity(0.26), accent.withOpacity(0.10)]),
                          border: Border.all(color: accent.withOpacity(0.22)),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(items.length, (i) {
                      final selected = i == index;
                      final it = items[i];
                      return Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => onTap(i),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: selected ? 1 : 0.74,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(it.icon, size: 22, color: selected ? accent.withOpacity(0.98) : Colors.white.withOpacity(0.75)),
                                const SizedBox(height: 4),
                                Text(
                                  it.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: selected ? accent.withOpacity(0.98) : Colors.white.withOpacity(0.75),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

class _PageScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _PageScaffold({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: [
          TopHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// =========================================================
///  SELLER SHELL (Firestore)
/// =========================================================

class SellerShell extends StatefulWidget {
  const SellerShell({super.key});

  @override
  State<SellerShell> createState() => _SellerShellState();
}

class _SellerShellState extends State<SellerShell> {
  final PageController _pc = PageController();
  int _i = 0;

  void _go(int i) {
    setState(() => _i = i);
    _pc.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  Future<Map<String, dynamic>> _myUserData() async {
    final u = currentUser!;
    final snap = await userDoc(u.uid).get();
    return snap.data() ?? {};
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _myUserData(),
      builder: (context, snap) {
        final name = (snap.data?['name'] ?? '').toString();

        return Scaffold(
          extendBody: true,
          appBar: AppBar(
            title: Text('Vendedor • $name'),
            
            actions: [
              IconButton(
  icon: const Icon(Icons.person),
  tooltip: 'Perfil',
  onPressed: () async {
    final snap = await userDoc(currentUser!.uid).get();
    final data = snap.data() ?? {};

    final name = (data['name'] ?? '').toString();
    final role = roleFromString((data['role'] ?? 'seller').toString());

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfilePage(
            name: name,
            role: role,
            onLogout: () {
              _auth.signOut();
              Navigator.popUntil(context, (r) => r.isFirst);
            },
          ),
        ),
      );
    }
  },
),
              IconButton(
                tooltip: 'Sair',
                onPressed: () => _auth.signOut(),
                icon: const Icon(Icons.logout),
              )
            ],
          ),
          body: PageView(
            controller: _pc,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (x) => setState(() => _i = x),
            children: const [
              SellerAddClientPage(),
              SellerClientsPage(),
              SellerSchedulePage(),
              SellerAgendaDayPage(),
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: GlassBottomNav(
              index: _i,
              onTap: _go,
              items: const [
                _NavItem(Icons.person_add_alt_1, 'Cadastrar'),
                _NavItem(Icons.view_list, 'Clientes'),
                _NavItem(Icons.event_available, 'Agendar'),
                _NavItem(Icons.calendar_month, 'Agenda'),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ---- SELLER: cadastrar cliente (Firestore) — MAIS DETALHADO

class SellerAddClientPage extends StatefulWidget {
  const SellerAddClientPage({super.key});

  @override
  State<SellerAddClientPage> createState() => _SellerAddClientPageState();
}

class _SellerAddClientPageState extends State<SellerAddClientPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _car = TextEditingController();
  final _plate = TextEditingController();
  final _color = TextEditingController();
  final _km = TextEditingController();
  final _notes = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _car.dispose();
    _plate.dispose();
    _color.dispose();
    _km.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final u = currentUser!;
    setState(() => saving = true);
    try {
      await clientsCol().add({
        'fullName': _fullName.text.trim(),
        'phone': _phone.text.trim(),
        'car': _car.text.trim(),
        'plate': _plate.text.trim().toUpperCase(),
        'color': _color.text.trim(),
        'km': int.tryParse(_km.text.trim()) ?? 0,
        'notes': _notes.text.trim(),
        'createdBy': u.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _fullName.clear();
      _phone.clear();
      _car.clear();
      _plate.clear();
      _color.clear();
      _km.clear();
      _notes.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente cadastrado!')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: 'Cadastrar cliente',
      subtitle: 'Cadastro completo',
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const SectionTitle('Dados do cliente'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _fullName,
              decoration: const InputDecoration(labelText: 'Nome completo', prefixIcon: Icon(Icons.person)),
              validator: (v) => (v == null || v.trim().split(' ').length < 2) ? 'Digite nome e sobrenome' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Telefone/WhatsApp', prefixIcon: Icon(Icons.phone)),
              validator: (v) => (v == null || v.trim().length < 8) ? 'Telefone inválido' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _car,
              decoration: const InputDecoration(labelText: 'Carro', prefixIcon: Icon(Icons.directions_car)),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Digite o carro' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _plate,
              decoration: const InputDecoration(labelText: 'Placa', prefixIcon: Icon(Icons.credit_card)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _color,
              decoration: const InputDecoration(labelText: 'Cor', prefixIcon: Icon(Icons.palette)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _km,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'KM atual', prefixIcon: Icon(Icons.speed)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Observações', prefixIcon: Icon(Icons.notes)),
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: saving ? null : _save,
                icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator()) : const Icon(Icons.check),
                label: const Text('Salvar cliente'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---- SELLER: lista + editar/excluir (Firestore)

class SellerClientsPage extends StatelessWidget {
  const SellerClientsPage({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    return clientsCol().orderBy('createdAt', descending: true).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: 'Clientes',
      subtitle: 'Editar e excluir',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Text('Carregando...', style: TextStyle(color: Colors.white.withOpacity(0.65)));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Text('Nenhum cliente ainda.', style: TextStyle(color: Colors.white.withOpacity(0.65)));
          }

          return Column(
            children: docs.map((d) {
              final data = d.data();
              final fullName = (data['fullName'] ?? '').toString();
              final phone = (data['phone'] ?? '').toString();
              final car = (data['car'] ?? '').toString();
              final plate = (data['plate'] ?? '').toString();
              final km = asInt(data['km']);
              final color = (data['color'] ?? '').toString();

              final sub = [
                if (phone.isNotEmpty) phone,
                if (car.isNotEmpty) car,
                if (plate.isNotEmpty) 'Placa: $plate',
                if (color.isNotEmpty) 'Cor: $color',
                if (km > 0) 'KM: $km',
              ].join(' • ');

              return NitroTile(
                icon: Icons.person,
                title: fullName,
                subtitle: sub.isEmpty ? '-' : sub,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Editar',
                      onPressed: () => _editClient(context, d.id, data),
                      icon: Icon(Icons.edit, color: Colors.white.withOpacity(0.78)),
                    ),
                    IconButton(
                      tooltip: 'Excluir',
                      onPressed: () async {
                        await clientsCol().doc(d.id).delete();
                      },
                      icon: Icon(Icons.delete_outline, color: Colors.redAccent.withOpacity(0.9)),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Future<void> _editClient(BuildContext context, String id, Map<String, dynamic> data) async {
    final name = TextEditingController(text: (data['fullName'] ?? '').toString());
    final ph = TextEditingController(text: (data['phone'] ?? '').toString());
    final cr = TextEditingController(text: (data['car'] ?? '').toString());
    final plate = TextEditingController(text: (data['plate'] ?? '').toString());
    final color = TextEditingController(text: (data['color'] ?? '').toString());
    final km = TextEditingController(text: asInt(data['km']).toString());
    final notes = TextEditingController(text: (data['notes'] ?? '').toString());

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1724),
        title: const Text('Editar cliente'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nome completo'),
                  validator: (v) => (v == null || v.trim().split(' ').length < 2) ? 'Nome e sobrenome' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: ph,
                  decoration: const InputDecoration(labelText: 'Telefone'),
                  validator: (v) => (v == null || v.trim().length < 8) ? 'Telefone inválido' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: cr,
                  decoration: const InputDecoration(labelText: 'Carro'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Carro obrigatório' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: plate,
                  decoration: const InputDecoration(labelText: 'Placa'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: color,
                  decoration: const InputDecoration(labelText: 'Cor'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: km,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'KM'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Observações'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await clientsCol().doc(id).update({
                'fullName': name.text.trim(),
                'phone': ph.text.trim(),
                'car': cr.text.trim(),
                'plate': plate.text.trim().toUpperCase(),
                'color': color.text.trim(),
                'km': int.tryParse(km.text.trim()) ?? 0,
                'notes': notes.text.trim(),
              });
              Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    name.dispose();
    ph.dispose();
    cr.dispose();
    plate.dispose();
    color.dispose();
    km.dispose();
    notes.dispose();
  }
}

/// ---- SELLER: agendar (Firestore) — com VALOR e KM Entrada

class SellerSchedulePage extends StatefulWidget {
  const SellerSchedulePage({super.key});

  @override
  State<SellerSchedulePage> createState() => _SellerSchedulePageState();
}

class _SellerSchedulePageState extends State<SellerSchedulePage> {
  String? _clientId;
  final _service = TextEditingController();
  final _notes = TextEditingController();
  final _price = TextEditingController();
  final _kmIn = TextEditingController();
  DateTime? _dt;
  bool saving = false;

  @override
  void dispose() {
    _service.dispose();
    _notes.dispose();
    _price.dispose();
    _kmIn.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dt ?? now,
      firstDate: now.subtract(const Duration(days: 0)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;

    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_dt ?? now));
    if (time == null) return;

    setState(() => _dt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (_clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um cliente.')));
      return;
    }
    if (_service.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Digite o serviço.')));
      return;
    }
    if (_dt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione data e hora.')));
      return;
    }

    final u = currentUser!;
    final price = int.tryParse(_price.text.trim()) ?? 0;
    final kmIn = int.tryParse(_kmIn.text.trim()) ?? 0;

    setState(() => saving = true);
    try {
      await apptsCol().add({
        'clientId': _clientId,
        'service': _service.text.trim(),
        'scheduledAt': Timestamp.fromDate(_dt!),
        'notes': _notes.text.trim(),
        'price': price,
        'kmIn': kmIn,
        'kmOut': null,
        'checkInAt': FieldValue.serverTimestamp(),
        'checkOutAt': null,
        'postChecklist': {},
        'status': statusToString(ApptStatus.scheduled),
        'operatorId': null,
        'operatorName': null,
        'startedAt': null,
        'finishedAt': null,
        'workedSeconds': 0,
        'createdBy': u.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _clientId = null;
        _service.clear();
        _notes.clear();
        _price.clear();
        _kmIn.clear();
        _dt = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agendamento criado!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: 'Agendar serviço',
      subtitle: 'Com valor + KM entrada',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Novo agendamento'),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: clientsCol().orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Text('Cadastre um cliente primeiro.', style: TextStyle(color: Colors.white.withOpacity(0.65)));
              }

              return DropdownButtonFormField<String>(
                value: _clientId,
                decoration: const InputDecoration(labelText: 'Cliente', prefixIcon: Icon(Icons.person)),
                items: docs.map((d) {
                  final data = d.data();
                  final fullName = (data['fullName'] ?? '').toString();
                  final car = (data['car'] ?? '').toString();
                  final plate = (data['plate'] ?? '').toString();
                  final label = [fullName, if (car.isNotEmpty) car, if (plate.isNotEmpty) plate].join(' • ');
                  return DropdownMenuItem(value: d.id, child: Text(label));
                }).toList(),
                onChanged: (v) => setState(() => _clientId = v),
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(controller: _service, decoration: const InputDecoration(labelText: 'Serviço', prefixIcon: Icon(Icons.build))),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _pickDateTime,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFF0F1724).withOpacity(0.92),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: const Color(0xFF3AA0FF).withOpacity(0.95)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _dt == null ? 'Selecione data e hora' : fmtDateTime(_dt!),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _dt == null ? Colors.white.withOpacity(0.65) : Colors.white.withOpacity(0.92),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.35)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Valor (R\$\ )', prefixIcon: Icon(Icons.attach_money)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _kmIn,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'KM Entrada', prefixIcon: Icon(Icons.speed)),
          ),
          const SizedBox(height: 12),
          TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Observações (opcional)', prefixIcon: Icon(Icons.notes))),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: saving ? null : _save,
              icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator()) : const Icon(Icons.check),
              label: const Text('Salvar agendamento'),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---- SELLER: agenda do dia + editar/excluir (Firestore)

class SellerAgendaDayPage extends StatefulWidget {
  const SellerAgendaDayPage({super.key});

  @override
  State<SellerAgendaDayPage> createState() => _SellerAgendaDayPageState();
}

class _SellerAgendaDayPageState extends State<SellerAgendaDayPage> {
  DateTime _day = DateTime.now();

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream(DateTime day) {
    final start = Timestamp.fromDate(dateOnly(day));
    final end = Timestamp.fromDate(dateOnly(day).add(const Duration(days: 1)));
    return apptsCol()
        .where('scheduledAt', isGreaterThanOrEqualTo: start)
        .where('scheduledAt', isLessThan: end)
        .orderBy('scheduledAt')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final day = dateOnly(_day);

    return _PageScaffold(
      title: 'Agenda do dia',
      subtitle: 'Editar agendamento',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.tonalIcon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: day,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked == null) return;
              setState(() => _day = picked);
            },
            icon: const Icon(Icons.calendar_today),
            label: Text(fmtDate(day)),
          ),
          const SizedBox(height: 16),
          SectionTitle('Agendamentos • ${fmtDate(day)}'),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stream(day),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Text('Carregando...', style: TextStyle(color: Colors.white.withOpacity(0.65)));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return Text('Nenhum agendamento.', style: TextStyle(color: Colors.white.withOpacity(0.65)));

              return Column(
                children: docs.map((d) {
                  final data = d.data();
                  final service = (data['service'] ?? '').toString();
                  final st = statusFromString((data['status'] ?? 'scheduled').toString());
                  final ts = (data['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final clientId = (data['clientId'] ?? '').toString();
                  final notes = (data['notes'] ?? '').toString();
                  final price = asInt(data['price']);
                  final kmIn = asInt(data['kmIn']);

                  final sub = [
                    'Cliente: $clientId',
                    if (price > 0) 'R\$ $price',
                    if (kmIn > 0) 'KM: $kmIn',
                    if (notes.isNotEmpty) notes,
                  ].join(' • ');

                  return NitroTile(
                    icon: Icons.event,
                    title: '$service • ${fmtTime(ts)} • ${_statusLabelLocal(st)}',
                    subtitle: sub,
                    onTap: () => _editAppointment(context, d.id, data),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  String _statusLabelLocal(ApptStatus s) {
    switch (s) {
      case ApptStatus.scheduled:
        return 'Agendado';
      case ApptStatus.inProgress:
        return 'Em execução';
      case ApptStatus.done:
        return 'Finalizado';
      case ApptStatus.canceled:
        return 'Cancelado';
    }
  }

  Future<void> _editAppointment(BuildContext context, String id, Map<String, dynamic> data) async {
    final svc = TextEditingController(text: (data['service'] ?? '').toString());
    final notes = TextEditingController(text: (data['notes'] ?? '').toString());
    final price = TextEditingController(text: asInt(data['price']).toString());
    final kmIn = TextEditingController(text: asInt(data['kmIn']).toString());

    var clientId = (data['clientId'] ?? '').toString();
    var dt = (data['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now();

    Future<void> pickDateTime(StateSetter setLocal) async {
      final date = await showDatePicker(
        context: context,
        initialDate: dt,
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (date == null) return;
      final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(dt));
      if (time == null) return;
      dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      setLocal(() {});
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF0F1724),
          title: const Text('Editar agendamento'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: clientsCol().orderBy('createdAt', descending: true).snapshots(),
                  builder: (context, snap) {
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) return const SizedBox.shrink();
                    return DropdownButtonFormField<String>(
                      value: clientId.isEmpty ? docs.first.id : clientId,
                      decoration: const InputDecoration(labelText: 'Cliente'),
                      items: docs.map((d) {
                        final fullName = (d.data()['fullName'] ?? '').toString();
                        return DropdownMenuItem(value: d.id, child: Text(fullName));
                      }).toList(),
                      onChanged: (v) => setLocal(() => clientId = v ?? clientId),
                    );
                  },
                ),
                const SizedBox(height: 10),
                TextField(controller: svc, decoration: const InputDecoration(labelText: 'Serviço')),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => pickDateTime(setLocal),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: const Color(0xFF0F1724).withOpacity(0.92),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.schedule, color: const Color(0xFF3AA0FF).withOpacity(0.95)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(fmtDateTime(dt), style: const TextStyle(fontWeight: FontWeight.w900))),
                        Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.35)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Valor (R\$\ )'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: kmIn,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'KM Entrada'),
                ),
                const SizedBox(height: 10),
                TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Observações')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            TextButton(
              onPressed: () async {
                await apptsCol().doc(id).delete();
                Navigator.pop(ctx);
              },
              child: const Text('Excluir'),
            ),
            FilledButton(
              onPressed: () async {
                await apptsCol().doc(id).update({
                  'clientId': clientId,
                  'service': svc.text.trim(),
                  'scheduledAt': Timestamp.fromDate(dt),
                  'price': int.tryParse(price.text.trim()) ?? 0,
                  'kmIn': int.tryParse(kmIn.text.trim()) ?? 0,
                  'notes': notes.text.trim(),
                });
                Navigator.pop(ctx);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    svc.dispose();
    notes.dispose();
    price.dispose();
    kmIn.dispose();
  }
}

/// =========================================================
///  OPS SHELL (Firestore)
/// =========================================================

class OpsShell extends StatefulWidget {
  const OpsShell({super.key});

  @override
  State<OpsShell> createState() => _OpsShellState();
}

class _OpsShellState extends State<OpsShell> {
  final PageController _pc = PageController();
  int _i = 0;

  void _go(int i) {
    setState(() => _i = i);
    _pc.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  Future<Map<String, dynamic>> _myUserData() async {
    final u = currentUser!;
    final snap = await userDoc(u.uid).get();
    return snap.data() ?? {};
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _myUserData(),
      builder: (context, snap) {
        final name = (snap.data?['name'] ?? '').toString();

        return Scaffold(
          extendBody: true,
          appBar: AppBar(
            title: Text('Operacional • $name'),
            actions: [
              IconButton(
  icon: const Icon(Icons.person),
  tooltip: 'Perfil',
  onPressed: () async {
    final snap = await userDoc(currentUser!.uid).get();
    final data = snap.data() ?? {};

    final name = (data['name'] ?? '').toString();
    final role = roleFromString((data['role'] ?? 'seller').toString());

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfilePage(
            name: name,
            role: role,
            onLogout: () {
              _auth.signOut();
              Navigator.popUntil(context, (r) => r.isFirst);
            },
          ),
        ),
      );
    }
  },
),
              IconButton(
                tooltip: 'Sair',
                onPressed: () => _auth.signOut(),
                icon: const Icon(Icons.logout),
              )
            ],
          ),
          body: PageView(
            controller: _pc,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (x) => setState(() => _i = x),
            children: const [
              OpsQueuePage(),
              OpsInProgressPage(),
              OpsAgendaPage(),
              OpsProductivityPage(),
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: GlassBottomNav(
              index: _i,
              onTap: _go,
              items: const [
                _NavItem(Icons.list_alt, 'Fila'),
                _NavItem(Icons.play_circle, 'Execução'),
                _NavItem(Icons.calendar_today, 'Agenda'),
                _NavItem(Icons.bar_chart, 'Produtividade'),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ---- OPS: fila do dia (Firestore)

class OpsQueuePage extends StatefulWidget {
  const OpsQueuePage({super.key});

  @override
  State<OpsQueuePage> createState() => _OpsQueuePageState();
}

class _OpsQueuePageState extends State<OpsQueuePage> {
  DateTime _day = DateTime.now();

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream(DateTime day) {
    final start = Timestamp.fromDate(dateOnly(day));
    final end = Timestamp.fromDate(dateOnly(day).add(const Duration(days: 1)));

    return apptsCol()
        .where('scheduledAt', isGreaterThanOrEqualTo: start)
        .where('scheduledAt', isLessThan: end)
        .orderBy('scheduledAt')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final day = dateOnly(_day);

    return _PageScaffold(
      title: 'Fila do dia',
      subtitle: 'Inicie serviços',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.tonalIcon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: day,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked == null) return;
              setState(() => _day = picked);
            },
            icon: const Icon(Icons.date_range),
            label: Text('Dia: ${fmtDate(day)}'),
          ),
          const SizedBox(height: 16),
          const SectionTitle('Serviços'),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stream(day),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Text('Carregando...', style: TextStyle(color: Colors.white.withOpacity(0.65)));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return Text('Nada na fila.', style: TextStyle(color: Colors.white.withOpacity(0.65)));

              final filtered = docs.where((d) {
                final s = statusFromString((d.data()['status'] ?? 'scheduled').toString());
                return s == ApptStatus.scheduled || s == ApptStatus.inProgress;
              }).toList();

              if (filtered.isEmpty) return Text('Nada na fila.', style: TextStyle(color: Colors.white.withOpacity(0.65)));

              return Column(
                children: filtered.map((d) {
                  final data = d.data();
                  final service = (data['service'] ?? '').toString();
                  final st = statusFromString((data['status'] ?? 'scheduled').toString());
                  final ts = (data['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final operatorId = (data['operatorId'] ?? '').toString();
                  final price = asInt(data['price']);
                  final kmIn = asInt(data['kmIn']);

                  final sub = st == ApptStatus.inProgress
                      ? 'Em execução por: ${data['operatorName'] ?? "-"}'
                      : [
                          'Aguardando início',
                          if (price > 0) 'R\$ $price',
                          if (kmIn > 0) 'KM: $kmIn',
                        ].join(' • ');

                  return NitroTile(
                    icon: st == ApptStatus.inProgress ? Icons.play_circle : Icons.timer,
                    title: '$service • ${fmtTime(ts)} • ${_statusLabelLocal(st)}',
                    subtitle: sub,
                    trailing: st == ApptStatus.inProgress
                        ? Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.35))
                        : FilledButton.tonal(
                            onPressed: () => _start(d.id),
                            child: const Text('Iniciar'),
                          ),
                    onTap: () {
                      if (st == ApptStatus.inProgress && operatorId == (currentUser?.uid ?? '')) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => OpsServicePage(apptId: d.id)));
                      }
                    },
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _start(String apptId) async {
    final u = currentUser!;
    final my = await userDoc(u.uid).get();
    final myName = (my.data()?['name'] ?? '').toString();

    await apptsCol().doc(apptId).update({
      'status': statusToString(ApptStatus.inProgress),
      'operatorId': u.uid,
      'operatorName': myName,
      'startedAt': FieldValue.serverTimestamp(),
      'finishedAt': null,
      'workedSeconds': 0,
    });

    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => OpsServicePage(apptId: apptId)));
    }
  }

  String _statusLabelLocal(ApptStatus s) {
    switch (s) {
      case ApptStatus.scheduled:
        return 'Agendado';
      case ApptStatus.inProgress:
        return 'Em execução';
      case ApptStatus.done:
        return 'Finalizado';
      case ApptStatus.canceled:
        return 'Cancelado';
    }
  }
}

/// ---- OPS: execução (lista do que está inProgress do operador)

class OpsInProgressPage extends StatelessWidget {
  const OpsInProgressPage({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    final u = currentUser!;
    return apptsCol()
        .where('status', isEqualTo: statusToString(ApptStatus.inProgress))
        .where('operatorId', isEqualTo: u.uid)
        .orderBy('scheduledAt')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: 'Execução',
      subtitle: 'O que você está fazendo agora',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Text('Carregando...', style: TextStyle(color: Colors.white.withOpacity(0.65)));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return Text('Nenhum serviço em execução.', style: TextStyle(color: Colors.white.withOpacity(0.65)));

          return Column(
            children: docs.map((d) {
              final data = d.data();
              final service = (data['service'] ?? '').toString();
              final ts = (data['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now();
              final price = asInt(data['price']);
              return NitroTile(
                icon: Icons.play_circle,
                title: '$service • ${fmtTime(ts)}',
                subtitle: price > 0 ? 'R\$ $price • Toque para abrir' : 'Toque para abrir',
                trailing: Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.35)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OpsServicePage(apptId: d.id))),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

/// ---- OPS: agenda (somente leitura do dia)

class OpsAgendaPage extends StatefulWidget {
  const OpsAgendaPage({super.key});

  @override
  State<OpsAgendaPage> createState() => _OpsAgendaPageState();
}

class _OpsAgendaPageState extends State<OpsAgendaPage> {
  DateTime _day = DateTime.now();

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream(DateTime day) {
    final start = Timestamp.fromDate(dateOnly(day));
    final end = Timestamp.fromDate(dateOnly(day).add(const Duration(days: 1)));
    return apptsCol()
        .where('scheduledAt', isGreaterThanOrEqualTo: start)
        .where('scheduledAt', isLessThan: end)
        .orderBy('scheduledAt')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final day = dateOnly(_day);

    return _PageScaffold(
      title: 'Agenda',
      subtitle: 'Somente leitura',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.tonalIcon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: day,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked == null) return;
              setState(() => _day = picked);
            },
            icon: const Icon(Icons.date_range),
            label: Text('Dia: ${fmtDate(day)}'),
          ),
          const SizedBox(height: 16),
          SectionTitle('Agendamentos • ${fmtDate(day)}'),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stream(day),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Text('Carregando...', style: TextStyle(color: Colors.white.withOpacity(0.65)));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return Text('Nada agendado.', style: TextStyle(color: Colors.white.withOpacity(0.65)));

              return Column(
                children: docs.map((d) {
                  final data = d.data();
                  final service = (data['service'] ?? '').toString();
                  final st = statusFromString((data['status'] ?? 'scheduled').toString());
                  final ts = (data['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final price = asInt(data['price']);
                  final sub = [
                    if ((data['operatorName'] ?? '').toString().isEmpty) 'Sem operador' else 'Operador: ${data['operatorName']}',
                    if (price > 0) 'R\$ $price',
                  ].join(' • ');

                  return NitroTile(
                    icon: Icons.event,
                    title: '$service • ${fmtTime(ts)} • ${_statusLabelLocal(st)}',
                    subtitle: sub,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  String _statusLabelLocal(ApptStatus s) {
    switch (s) {
      case ApptStatus.scheduled:
        return 'Agendado';
      case ApptStatus.inProgress:
        return 'Em execução';
      case ApptStatus.done:
        return 'Finalizado';
      case ApptStatus.canceled:
        return 'Cancelado';
    }
  }
}

/// ---- OPS: produtividade (done do operador) — CORRIGIDA

class OpsProductivityPage extends StatelessWidget {
  const OpsProductivityPage({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    final u = currentUser!;
    return apptsCol()
        .where('status', isEqualTo: statusToString(ApptStatus.done))
        .where('operatorId', isEqualTo: u.uid)
        .orderBy('finishedAt', descending: true) // pode exigir índice
        .snapshots();
  }

  String fmtDuration(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: 'Produtividade',
      subtitle: 'Em tempo real (Firestore)',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream(),
        builder: (context, snap) {
          if (snap.hasError) {
            final msg = snap.error.toString();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NitroTile(
                  icon: Icons.error_outline,
                  title: 'Erro ao carregar produtividade',
                  subtitle: msg.contains('FAILED_PRECONDITION') || msg.contains('index')
                      ? 'Falta criar índice no Firestore.\nAbra o erro no console e clique no link "Create index".'
                      : msg,
                ),
              ],
            );
          }

          if (snap.connectionState == ConnectionState.waiting) {
            return Text('Carregando...', style: TextStyle(color: Colors.white.withOpacity(0.65)));
          }

          final docs = snap.data?.docs ?? [];

          int total = 0;
          for (final d in docs) {
            total += asInt(d.data()['workedSeconds']);
          }
          final avg = docs.isEmpty ? 0 : (total / docs.length).round();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NitroTile(icon: Icons.check_circle, title: 'Serviços finalizados', subtitle: '${docs.length}'),
              NitroTile(icon: Icons.timer, title: 'Tempo total', subtitle: fmtDuration(total)),
              NitroTile(icon: Icons.speed, title: 'Tempo médio', subtitle: fmtDuration(avg)),
              const SizedBox(height: 10),
              const SectionTitle('Últimos serviços'),
              const SizedBox(height: 10),
              ...docs.take(10).map((d) {
                final data = d.data();
                final service = (data['service'] ?? '').toString();
                final sec = asInt(data['workedSeconds']);
                final fin = (data['finishedAt'] as Timestamp?)?.toDate();
                final when = fin == null ? '-' : fmtDateTime(fin);
                return NitroTile(icon: Icons.history, title: service, subtitle: '$when • ${fmtDuration(sec)}');
              }),
            ],
          );
        },
      ),
    );
  }
}

/// ---- OPS: Service page (timer + checklist + finalizar) — salva no Firestore

class OpsServicePage extends StatefulWidget {
  final String apptId;
  const OpsServicePage({super.key, required this.apptId});

  @override
  State<OpsServicePage> createState() => _OpsServicePageState();
}

class _OpsServicePageState extends State<OpsServicePage> {
  Timer? _ticker;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += 1);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _fmtDuration(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  Future<void> _openPostChecklist(BuildContext context, DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) async {
    final raw = data['postChecklist'];
    final current = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final doneCount = postChecklistItems.keys.where((k) => current[k] == true).length;
          return AlertDialog(
            backgroundColor: const Color(0xFF0F1724),
            title: Text('Checklist final ($doneCount/${postChecklistItems.length})'),
            content: SingleChildScrollView(
              child: Column(
                children: postChecklistItems.entries.map((e) {
                  final k = e.key;
                  final label = e.value;
                  final checked = current[k] == true;
                  return CheckboxListTile(
                    value: checked,
                    onChanged: (v) => setLocal(() => current[k] = (v == true)),
                    title: Text(label),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () async {
                  await ref.update({'postChecklist': current});
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checklist salvo.')));
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = apptsCol().doc(widget.apptId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const _LoadingPage(text: 'Carregando serviço...');
        }

        final data = snap.data!.data() ?? {};
        final service = (data['service'] ?? '').toString();
        final st = statusFromString((data['status'] ?? 'scheduled').toString());
        final ts = (data['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        final storedSeconds = asInt(data['workedSeconds']);
        final price = asInt(data['price']);
        final kmIn = asInt(data['kmIn']);

        // sincroniza com banco (sem reduzir)
        if (_elapsed < storedSeconds) _elapsed = storedSeconds;

        final rawPost = data['postChecklist'];
        final post = rawPost is Map ? Map<String, dynamic>.from(rawPost) : <String, dynamic>{};
        final postDone = postChecklistItems.keys.every((k) => post[k] == true);

        return Scaffold(
          appBar: AppBar(title: const Text('Execução do serviço')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              children: [
                TopHeader(
                  title: service,
                  subtitle: 'Agendado: ${fmtDateTime(ts)}${price > 0 ? " • R\$ $price" : ""}${kmIn > 0 ? " • KM: $kmIn" : ""}',
                ),
                const SizedBox(height: 16),
                NitroTile(icon: Icons.play_circle, title: 'Status', subtitle: _statusLabel(st)),
                const SizedBox(height: 8),
                const SectionTitle('Timer'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: const Color(0xFF0F1724).withOpacity(0.92),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer),
                      const SizedBox(width: 10),
                      Text(_fmtDuration(_elapsed), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      const Spacer(),
                      FilledButton.tonal(
                        onPressed: st == ApptStatus.inProgress
                            ? () async {
                                await ref.update({'workedSeconds': _elapsed});
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tempo salvo.')));
                              }
                            : null,
                        child: const Text('Salvar'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                const SectionTitle('Checklist final'),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: FilledButton.tonalIcon(
                    onPressed: st == ApptStatus.inProgress ? () => _openPostChecklist(context, ref, data) : null,
                    icon: const Icon(Icons.checklist),
                    label: Text(postDone ? 'Checklist completo ✅' : 'Abrir checklist'),
                  ),
                ),

                const SizedBox(height: 16),
                const SectionTitle('Finalização'),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: (st == ApptStatus.inProgress && postDone)
                        ? () async {
                            await ref.update({
                              'status': statusToString(ApptStatus.done),
                              'finishedAt': FieldValue.serverTimestamp(),
                              'checkOutAt': FieldValue.serverTimestamp(),
                              'workedSeconds': _elapsed,
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Serviço finalizado!')));
                              Navigator.pop(context);
                            }
                          }
                        : null,
                    icon: const Icon(Icons.check_circle),
                    label: Text(postDone ? 'Finalizar serviço' : 'Finalize o checklist primeiro'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _statusLabel(ApptStatus s) {
    switch (s) {
      case ApptStatus.scheduled:
        return 'Agendado';
      case ApptStatus.inProgress:
        return 'Em execução';
      case ApptStatus.done:
        return 'Finalizado';
      case ApptStatus.canceled:
        return 'Cancelado';
    }
  }
}

/// =========================================================
///  Shared helper
/// =========================================================

String _statusLabel(ApptStatus s) {
  switch (s) {
    case ApptStatus.scheduled:
      return 'Agendado';
    case ApptStatus.inProgress:
      return 'Em execução';
    case ApptStatus.done:
      return 'Finalizado';
    case ApptStatus.canceled:
      return 'Cancelado';
  }
}
// ===============================
// PROFILE PAGE
// ===============================

class ProfilePage extends StatelessWidget {
  final String name;
  final Role role;
  final VoidCallback onLogout;

  const ProfilePage({
    super.key,
    required this.name,
    required this.role,
    required this.onLogout,
  });

  String roleText(Role r) {
    switch (r) {
      case Role.seller:
        return 'Vendedor';
      case Role.ops:
        return 'Operacional';
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          children: [

            TopHeader(
              title: name.isEmpty ? 'Nitro Staff' : name,
              subtitle: u?.email ?? '',
            ),

            const SizedBox(height: 16),

            NitroTile(
              icon: Icons.verified_user,
              title: 'Perfil atual',
              subtitle: roleText(role),
            ),

            NitroTile(
              icon: Icons.fingerprint,
              title: 'UID',
              subtitle: u?.uid ?? '',
            ),

            const SizedBox(height: 18),
            const SectionTitle('Funções de Vendedor'),
            const SizedBox(height: 10),

            NitroTile(
              icon: Icons.person_add,
              title: 'Cadastrar Cliente',
              subtitle: 'Adicionar novo cliente',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SellerAddClientPage(),
                  ),
                );
              },
            ),

            NitroTile(
              icon: Icons.people,
              title: 'Clientes',
              subtitle: 'Lista de clientes',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SellerClientsPage(),
                  ),
                );
              },
            ),

            NitroTile(
              icon: Icons.event_available,
              title: 'Agendar Serviço',
              subtitle: 'Criar agendamento',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SellerSchedulePage(),
                  ),
                );
              },
            ),

            NitroTile(
              icon: Icons.calendar_month,
              title: 'Agenda do Dia',
              subtitle: 'Editar agendamentos',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SellerAgendaDayPage(),
                  ),
                );
              },
            ),

            const SizedBox(height: 18),
            const SectionTitle('Funções Operacionais'),
            const SizedBox(height: 10),

            NitroTile(
              icon: Icons.list_alt,
              title: 'Fila do Dia',
              subtitle: 'Iniciar serviços',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OpsQueuePage(),
                  ),
                );
              },
            ),

            NitroTile(
              icon: Icons.play_circle,
              title: 'Serviços em Execução',
              subtitle: 'Ver serviços ativos',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OpsInProgressPage(),
                  ),
                );
              },
            ),

            NitroTile(
              icon: Icons.calendar_today,
              title: 'Agenda Operacional',
              subtitle: 'Agenda de serviços',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OpsAgendaPage(),
                  ),
                );
              },
            ),

            NitroTile(
              icon: Icons.bar_chart,
              title: 'Produtividade',
              subtitle: 'Tempo e serviços',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OpsProductivityPage(),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout),
                label: const Text('Sair'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}