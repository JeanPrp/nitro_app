// lib/main.dart
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

/// ---------------------------------------------------------
/// Firestore (NOVO schema base)
///
/// users/{uid}: { name, role: "seller"|"ops"|"admin", createdAt }
///
/// clients/{id}:
///   { fullName, phone, car, plate, color, notes, createdBy, createdAt }
///
/// appointments/{id}:
///   {
///     clientId,
///     scheduledAt,
///     notes,
///
///     services: [ { name, price } ],
///     totalPrice,
///
///     payment: { status: "unpaid"|"partial"|"paid", paidAmount, paidAt },
///
///     checkIn:  { km, items(map), confirmedServices(bool), createdAt },
///     checkOut: { km, items(map), createdAt },
///
///     status: "scheduled"|"inProgress"|"done"|"canceled",
///     operatorId, operatorName,
///     startedAt, finishedAt, workedSeconds,
///
///     createdBy, createdAt
///   }
/// ---------------------------------------------------------

enum ApptStatus { scheduled, inProgress, done, canceled }
enum Role { seller, ops, admin }

Role roleFromString(String s) {
  if (s == 'ops') return Role.ops;
  if (s == 'admin') return Role.admin;
  return Role.seller;
}

String roleToString(Role r) {
  switch (r) {
    case Role.ops:
      return 'ops';
    case Role.admin:
      return 'admin';
    case Role.seller:
      return 'seller';
  }
}

String statusToString(ApptStatus s) {
  switch (s) {
    case ApptStatus.scheduled:
      return 'scheduled';
    case ApptStatus.inProgress:
      return 'inProgress';
    case ApptStatus.done:
      return 'done';
    case ApptStatus.canceled:
      return 'canceled';
  }
}

ApptStatus statusFromString(String s) {
  if (s == 'inProgress') return ApptStatus.inProgress;
  if (s == 'done') return ApptStatus.done;
  if (s == 'canceled') return ApptStatus.canceled;
  return ApptStatus.scheduled;
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

String brl(int v) => 'R\$ $v';

/// ===============================
/// Serviços fixos
/// ===============================
const kServiceTypes = <String>[
  'Lavagem tradicional',
  'Lavagem detalhada',
  'Lavagem detalhada 2',
  'Lavagem detalhada 3',
  'Higinização',
  'Troca de feltros',
  'Revitalização de plásticos e borrachas',
  'Polimento',
  'Polimento de vidro',
  'Polimento de farol',
  'PPF',
  'Martelinho',
  'Vitrificação',
  'Outro',
];

const kDefaultPriceByService = <String, int>{
  'Lavagem tradicional': 120,
  'Lavagem detalhada': 180,
  'Lavagem detalhada 2': 250,
  'Lavagem detalhada 3': 320,
  'Higinização': 220,
  'Troca de feltros': 80,
  'Revitalização de plásticos e borrachas': 90,
  'Polimento': 600,
  'Polimento de vidro': 250,
  'Polimento de farol': 160,
  'PPF': 15000,
  'Martelinho': 350,
  'Vitrificação': 900,
  'Outro': 0,
};

/// ===============================
/// Checklists
/// ===============================
const preChecklistItems = <String, String>{
  'pics_taken': 'Fotos tiradas (frente/lados/traseira/rodas)',
  'paint_risk': 'Risco/marca pré-existente identificado',
  'dents_risk': 'Amassado pré-existente identificado',
  'glass_risk': 'Trinca/arranhão em vidro identificado',
  'wheels_risk': 'Risco em roda identificado',
  'interior_items': 'Pertences do cliente conferidos/registrados',
  'fuel_level': 'Nível de combustível conferido (se necessário)',
  'confirm_service': 'Serviço confirmado com o cliente/agendamento',
};

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

/// ===============================
/// Helpers de serviços
/// ===============================
String servicesLabel(List services) {
  final names = <String>[];
  for (final s in services) {
    if (s is Map && (s['name'] ?? '').toString().trim().isNotEmpty) {
      names.add(s['name'].toString());
    }
  }
  return names.isEmpty ? '-' : names.join(' + ');
}

int calcTotalPrice(List services) {
  int sum = 0;
  for (final s in services) {
    if (s is Map) sum += asInt(s['price']);
  }
  return sum;
}

/// ===============================
/// Firebase
/// ===============================
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
/// AUTH GATE
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
            if (doc == null || !doc.exists) return const RoleSetupPage();

            final data = doc.data() ?? {};
            final role = roleFromString((data['role'] ?? 'seller').toString());

            if (role == Role.admin) return const AdminShell();
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
/// LOGIN + CADASTRO
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
                icon: loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator())
                    : const Icon(Icons.login),
                label: Text(isLogin ? 'Entrar' : 'Criar conta'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================
/// PRIMEIRO ACESSO: nome + role (seller/ops/admin)
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
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ChoiceChip(
                  selected: role == Role.seller,
                  label: const Text('Vendedor'),
                  onSelected: (_) => setState(() => role = Role.seller),
                ),
                ChoiceChip(
                  selected: role == Role.ops,
                  label: const Text('Operacional'),
                  onSelected: (_) => setState(() => role = Role.ops),
                ),
                ChoiceChip(
                  selected: role == Role.admin,
                  label: const Text('Admin'),
                  onSelected: (_) => setState(() => role = Role.admin),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: saving ? null : save,
                icon: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator())
                    : const Icon(Icons.check),
                label: const Text('Salvar e continuar'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Depois você pode travar isso por regra (somente admin define perfil).',
              style: TextStyle(color: Colors.white.withOpacity(0.65)),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================
/// UI base
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
/// PROFILE PAGE (com funções por role)
/// =========================================================
class ProfilePage extends StatelessWidget {
  final String name;
  final Role role;
  final VoidCallback onLogout;

  const ProfilePage({super.key, required this.name, required this.role, required this.onLogout});

  String roleText(Role r) {
    switch (r) {
      case Role.seller:
        return 'Vendedor';
      case Role.ops:
        return 'Operacional';
      case Role.admin:
        return 'Admin';
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = currentUser;

    final showSeller = role == Role.seller || role == Role.admin;
    final showOps = role == Role.ops || role == Role.admin;

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          children: [
            TopHeader(title: name.isEmpty ? 'Nitro Staff' : name, subtitle: u?.email ?? ''),
            const SizedBox(height: 16),
            NitroTile(icon: Icons.verified_user, title: 'Perfil atual', subtitle: roleText(role)),
            NitroTile(icon: Icons.fingerprint, title: 'UID', subtitle: u?.uid ?? ''),
            const SizedBox(height: 18),

            if (showSeller) ...[
              const SectionTitle('Funções de Vendedor'),
              const SizedBox(height: 10),
              NitroTile(
                icon: Icons.person_add,
                title: 'Cadastrar Cliente',
                subtitle: 'Adicionar novo cliente',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SellerAddClientPage())),
              ),
              NitroTile(
                icon: Icons.people,
                title: 'Clientes',
                subtitle: 'Lista de clientes',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SellerClientsPage())),
              ),
              NitroTile(
                icon: Icons.event_available,
                title: 'Agendar Serviço',
                subtitle: 'Multi-serviços + preço por item',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SellerSchedulePage())),
              ),
              NitroTile(
                icon: Icons.calendar_month,
                title: 'Agenda do Dia',
                subtitle: 'Editar agendamentos',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SellerAgendaDayPage())),
              ),
              const SizedBox(height: 18),
            ],

            if (showOps) ...[
              const SectionTitle('Funções Operacionais'),
              const SizedBox(height: 10),
              NitroTile(
                icon: Icons.list_alt,
                title: 'Fila do Dia',
                subtitle: 'Iniciar serviços',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OpsQueuePage())),
              ),
              NitroTile(
                icon: Icons.play_circle,
                title: 'Serviços em Execução',
                subtitle: 'Ver serviços ativos',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OpsInProgressPage())),
              ),
              NitroTile(
                icon: Icons.calendar_today,
                title: 'Agenda Operacional',
                subtitle: 'Somente leitura',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OpsAgendaPage())),
              ),
              NitroTile(
                icon: Icons.bar_chart,
                title: 'Produtividade',
                subtitle: 'Farol do mês + por serviço + por funcionário',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OpsProductivityPage())),
              ),
              const SizedBox(height: 18),
            ],

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

/// =========================================================
/// SHELLS
/// =========================================================
Future<Map<String, dynamic>> _myUserData() async {
  final u = currentUser!;
  final snap = await userDoc(u.uid).get();
  return snap.data() ?? {};
}

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
              ),
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
              ),
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
                _NavItem(Icons.bar_chart, 'Prod'),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ADMIN: tudo junto (seller + ops)
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final PageController _pc = PageController();
  int _i = 0;

  void _go(int i) {
    setState(() => _i = i);
    _pc.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
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
            title: Text('Admin • $name'),
            actions: [
              IconButton(
                icon: const Icon(Icons.person),
                tooltip: 'Perfil',
                onPressed: () async {
                  final snap = await userDoc(currentUser!.uid).get();
                  final data = snap.data() ?? {};
                  final name = (data['name'] ?? '').toString();
                  final role = roleFromString((data['role'] ?? 'admin').toString());
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
              IconButton(tooltip: 'Sair', onPressed: () => _auth.signOut(), icon: const Icon(Icons.logout)),
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
              OpsQueuePage(),
              OpsProductivityPage(),
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: GlassBottomNav(
              index: _i,
              onTap: _go,
              items: const [
                _NavItem(Icons.person_add_alt_1, 'Cad'),
                _NavItem(Icons.view_list, 'Cli'),
                _NavItem(Icons.event_available, 'Ag'),
                _NavItem(Icons.calendar_month, 'Agenda'),
                _NavItem(Icons.list_alt, 'Fila'),
                _NavItem(Icons.bar_chart, 'Prod'),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// =========================================================
/// SELLER PAGES
/// =========================================================
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
  final _notes = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _car.dispose();
    _plate.dispose();
    _color.dispose();
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
        'notes': _notes.text.trim(),
        'createdBy': u.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _fullName.clear();
      _phone.clear();
      _car.clear();
      _plate.clear();
      _color.clear();
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
            TextFormField(controller: _plate, decoration: const InputDecoration(labelText: 'Placa', prefixIcon: Icon(Icons.credit_card))),
            const SizedBox(height: 12),
            TextFormField(controller: _color, decoration: const InputDecoration(labelText: 'Cor', prefixIcon: Icon(Icons.palette))),
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
                icon: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator())
                    : const Icon(Icons.check),
                label: const Text('Salvar cliente'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
              final color = (data['color'] ?? '').toString();

              final sub = [
                if (phone.isNotEmpty) phone,
                if (car.isNotEmpty) car,
                if (plate.isNotEmpty) 'Placa: $plate',
                if (color.isNotEmpty) 'Cor: $color',
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
                      onPressed: () async => clientsCol().doc(d.id).delete(),
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
                TextFormField(controller: plate, decoration: const InputDecoration(labelText: 'Placa')),
                const SizedBox(height: 10),
                TextFormField(controller: color, decoration: const InputDecoration(labelText: 'Cor')),
                const SizedBox(height: 10),
                TextFormField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Observações')),
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
    notes.dispose();
  }
}

/// =========================================================
/// SELLER — Agendar (multi-serviços)
/// =========================================================
class SellerSchedulePage extends StatefulWidget {
  const SellerSchedulePage({super.key});

  @override
  State<SellerSchedulePage> createState() => _SellerSchedulePageState();
}

class _SellerSchedulePageState extends State<SellerSchedulePage> {
  String? _clientId;
  final _notes = TextEditingController();

  DateTime? _dt;
  bool saving = false;

  final List<Map<String, dynamic>> _services = [];
  final _otherName = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    _otherName.dispose();
    super.dispose();
  }

  int get _totalPrice => calcTotalPrice(_services);

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

  void _toggleService(String name) {
    final idx = _services.indexWhere((x) => (x['name'] ?? '') == name);
    if (idx >= 0) {
      setState(() => _services.removeAt(idx));
      return;
    }
    final defaultPrice = kDefaultPriceByService[name] ?? 0;
    setState(() {
      _services.add({'name': name, 'price': defaultPrice});
    });
  }

  Future<void> _editServicePrice(int index) async {
    final priceCtrl = TextEditingController(text: asInt(_services[index]['price']).toString());
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1724),
        title: Text('Preço • ${_services[index]['name']}'),
        content: TextField(
          controller: priceCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Valor (R\$)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(priceCtrl.text.trim()) ?? 0;
              setState(() => _services[index]['price'] = v);
              Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    priceCtrl.dispose();
  }

  void _addOther() {
    final name = _otherName.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _services.add({'name': name, 'price': 0});
      _otherName.clear();
    });
  }

  Future<void> _save() async {
    if (_clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um cliente.')));
      return;
    }
    if (_services.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione pelo menos 1 serviço.')));
      return;
    }
    if (_dt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione data e hora.')));
      return;
    }

    final u = currentUser!;
    setState(() => saving = true);

    try {
      await apptsCol().add({
        'clientId': _clientId,
        'scheduledAt': Timestamp.fromDate(_dt!),
        'notes': _notes.text.trim(),

        'services': _services,
        'totalPrice': _totalPrice,

        'payment': {'status': 'unpaid', 'paidAmount': 0, 'paidAt': null},
        'checkIn': {'km': null, 'items': {}, 'confirmedServices': false, 'createdAt': null},
        'checkOut': {'km': null, 'items': {}, 'createdAt': null},

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
        _notes.clear();
        _services.clear();
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
      subtitle: 'Vários serviços + preço por item',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Cliente'),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: clientsCol().orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return Text('Cadastre um cliente primeiro.', style: TextStyle(color: Colors.white.withOpacity(0.65)));

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

          const SizedBox(height: 16),
          const SectionTitle('Serviços (multi)'),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kServiceTypes.where((s) => s != 'Outro').map((s) {
              final selected = _services.any((x) => x['name'] == s);
              return ChoiceChip(
                selected: selected,
                label: Text(s),
                onSelected: (_) => _toggleService(s),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _otherName,
                  decoration: const InputDecoration(labelText: 'Outro (nome do serviço)'),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(onPressed: _addOther, child: const Text('Add')),
            ],
          ),

          const SizedBox(height: 12),
          if (_services.isNotEmpty) ...[
            const SectionTitle('Itens selecionados'),
            const SizedBox(height: 10),
            ..._services.asMap().entries.map((e) {
              final i = e.key;
              final it = e.value;
              final name = (it['name'] ?? '').toString();
              final price = asInt(it['price']);
              return NitroTile(
                icon: Icons.check_circle_outline,
                title: name,
                subtitle: price > 0 ? '${brl(price)} • toque para editar preço' : 'Preço: ${brl(0)} • toque para editar',
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _services.removeAt(i)),
                ),
                onTap: () => _editServicePrice(i),
              );
            }),
            NitroTile(icon: Icons.attach_money, title: 'Total', subtitle: brl(_totalPrice)),
          ],

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
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Observações (opcional)', prefixIcon: Icon(Icons.notes)),
          ),

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

/// =========================================================
/// SELLER — Agenda do dia (já lendo schema novo)
/// =========================================================
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
      subtitle: 'Editar agendamento (multi)',
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
                  final st = statusFromString((data['status'] ?? 'scheduled').toString());
                  final ts = (data['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now();

                  final services = (data['services'] as List?) ?? const [];
                  final serviceText = servicesLabel(services);
                  final totalPrice = asInt(data['totalPrice'], def: calcTotalPrice(services));

                  final clientId = (data['clientId'] ?? '').toString();
                  final notes = (data['notes'] ?? '').toString();

                  final sub = [
                    'Cliente: $clientId',
                    if (totalPrice > 0) brl(totalPrice),
                    if (notes.isNotEmpty) notes,
                  ].join(' • ');

                  return NitroTile(
                    icon: Icons.event,
                    title: '$serviceText • ${fmtTime(ts)} • ${_statusLabelLocal(st)}',
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
    // editor simples: notas + data/hora + pagamento (opcional)
    final notes = TextEditingController(text: (data['notes'] ?? '').toString());

    var clientId = (data['clientId'] ?? '').toString();
    var dt = (data['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now();

    final services = List<Map<String, dynamic>>.from(((data['services'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final otherName = TextEditingController();

    void toggleSvc(String name, StateSetter setLocal) {
      final idx = services.indexWhere((x) => (x['name'] ?? '') == name);
      if (idx >= 0) {
        services.removeAt(idx);
      } else {
        services.add({'name': name, 'price': kDefaultPriceByService[name] ?? 0});
      }
      setLocal(() {});
    }

    Future<void> editPrice(int i, StateSetter setLocal) async {
      final c = TextEditingController(text: asInt(services[i]['price']).toString());
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0F1724),
          title: Text('Preço • ${services[i]['name']}'),
          content: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Valor (R\$)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                services[i]['price'] = int.tryParse(c.text.trim()) ?? 0;
                Navigator.pop(ctx);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      );
      c.dispose();
      setLocal(() {});
    }

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
        builder: (ctx, setLocal) {
          final total = calcTotalPrice(services);
          return AlertDialog(
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

                  const SizedBox(height: 14),
                  const Align(alignment: Alignment.centerLeft, child: SectionTitle('Serviços (multi)')),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kServiceTypes.where((s) => s != 'Outro').map((s) {
                      final selected = services.any((x) => x['name'] == s);
                      return ChoiceChip(
                        selected: selected,
                        label: Text(s),
                        onSelected: (_) => toggleSvc(s, setLocal),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: otherName, decoration: const InputDecoration(labelText: 'Outro (nome)'))),
                      const SizedBox(width: 10),
                      FilledButton.tonal(
                        onPressed: () {
                          final n = otherName.text.trim();
                          if (n.isEmpty) return;
                          services.add({'name': n, 'price': 0});
                          otherName.clear();
                          setLocal(() {});
                        },
                        child: const Text('Add'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  if (services.isNotEmpty) ...[
                    ...services.asMap().entries.map((e) {
                      final i = e.key;
                      final it = e.value;
                      return NitroTile(
                        icon: Icons.check_circle_outline,
                        title: (it['name'] ?? '').toString(),
                        subtitle: '${brl(asInt(it['price']))} • toque para editar',
                        trailing: IconButton(icon: const Icon(Icons.close), onPressed: () { services.removeAt(i); setLocal(() {}); }),
                        onTap: () => editPrice(i, setLocal),
                      );
                    }),
                    NitroTile(icon: Icons.attach_money, title: 'Total', subtitle: brl(total)),
                  ],

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
                    'scheduledAt': Timestamp.fromDate(dt),
                    'services': services,
                    'totalPrice': calcTotalPrice(services),
                    'notes': notes.text.trim(),
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );

    notes.dispose();
    otherName.dispose();
  }
}

/// =========================================================
/// OPS PAGES
/// =========================================================
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
                  final st = statusFromString((data['status'] ?? 'scheduled').toString());
                  final ts = (data['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final operatorId = (data['operatorId'] ?? '').toString();

                  final services = (data['services'] as List?) ?? const [];
                  final service = servicesLabel(services);
                  final totalPrice = asInt(data['totalPrice'], def: calcTotalPrice(services));

                  final checkIn = data['checkIn'] is Map ? Map<String, dynamic>.from(data['checkIn']) : <String, dynamic>{};
                  final kmIn = asInt(checkIn['km']);

                  final sub = st == ApptStatus.inProgress
                      ? 'Em execução por: ${data['operatorName'] ?? "-"}'
                      : [
                          'Aguardando início',
                          if (totalPrice > 0) brl(totalPrice),
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

    await apptsCol().doc(apptId).set({
      'status': statusToString(ApptStatus.inProgress),
      'operatorId': u.uid,
      'operatorName': myName,
      'startedAt': FieldValue.serverTimestamp(),
      'finishedAt': null,
      'workedSeconds': 0,
      'payment': {'status': 'unpaid', 'paidAmount': 0, 'paidAt': null},
      'checkIn': {'km': null, 'items': {}, 'confirmedServices': false, 'createdAt': null},
      'checkOut': {'km': null, 'items': {}, 'createdAt': null},
    }, SetOptions(merge: true));

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

class OpsInProgressPage extends StatelessWidget {
  const OpsInProgressPage({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    final u = currentUser!;
    // evita índice complexo: filtra status no app (query simples por operatorId)
    return apptsCol()
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
          final docs = (snap.data?.docs ?? []).where((d) {
            final st = statusFromString((d.data()['status'] ?? '').toString());
            return st == ApptStatus.inProgress;
          }).toList();

          if (docs.isEmpty) return Text('Nenhum serviço em execução.', style: TextStyle(color: Colors.white.withOpacity(0.65)));

          return Column(
            children: docs.map((d) {
              final data = d.data();
              final services = (data['services'] as List?) ?? const [];
              final service = servicesLabel(services);
              final ts = (data['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now();
              final totalPrice = asInt(data['totalPrice'], def: calcTotalPrice(services));

              return NitroTile(
                icon: Icons.play_circle,
                title: '$service • ${fmtTime(ts)}',
                subtitle: totalPrice > 0 ? '${brl(totalPrice)} • Toque para abrir' : 'Toque para abrir',
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
                  final st = statusFromString((data['status'] ?? 'scheduled').toString());
                  final ts = (data['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now();

                  final services = (data['services'] as List?) ?? const [];
                  final service = servicesLabel(services);
                  final totalPrice = asInt(data['totalPrice'], def: calcTotalPrice(services));

                  final sub = [
                    ((data['operatorName'] ?? '').toString().isEmpty) ? 'Sem operador' : 'Operador: ${data['operatorName']}',
                    if (totalPrice > 0) brl(totalPrice),
                  ].join(' • ');

                  return NitroTile(icon: Icons.event, title: '$service • ${fmtTime(ts)} • ${_statusLabelLocal(st)}', subtitle: sub);
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

/// =========================================================
/// PRODUTIVIDADE — FAROL DO MÊS (valor total, pago, por serviço, por funcionário)
/// =========================================================
class OpsProductivityPage extends StatefulWidget {
  const OpsProductivityPage({super.key});

  @override
  State<OpsProductivityPage> createState() => _OpsProductivityPageState();
}

class _OpsProductivityPageState extends State<OpsProductivityPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  DateTime get _monthStart => DateTime(_month.year, _month.month, 1);
  DateTime get _monthEnd => DateTime(_month.year, _month.month + 1, 1);

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamMonth() {
    // Query simples: finishedAt range (evita índice com status/operator)
    return apptsCol()
        .where('finishedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_monthStart))
        .where('finishedAt', isLessThan: Timestamp.fromDate(_monthEnd))
        .orderBy('finishedAt', descending: true)
        .snapshots();
  }

  Future<void> _pickMonth() async {
    // Month picker simples usando DatePicker (pega dia 1)
    final picked = await showDatePicker(
      context: context,
      initialDate: _monthStart,
      firstDate: DateTime(DateTime.now().year - 2, 1, 1),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
    );
    if (picked == null) return;
    setState(() => _month = DateTime(picked.year, picked.month, 1));
  }

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: 'Produtividade',
      subtitle: 'Farol do mês (valores + serviços + equipe)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.tonalIcon(
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_month),
            label: Text('Mês: ${two(_month.month)}/${_month.year}'),
          ),
          const SizedBox(height: 14),

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _streamMonth(),
            builder: (context, snap) {
              if (snap.hasError) {
                return NitroTile(icon: Icons.error_outline, title: 'Erro ao carregar', subtitle: snap.error.toString());
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return Text('Carregando...', style: TextStyle(color: Colors.white.withOpacity(0.65)));
              }

              final docs = snap.data?.docs ?? [];

              int totalSold = 0;
              int totalPaid = 0;
              int totalCount = 0;

              final byServiceValue = <String, int>{};
              final byEmployeeValue = <String, int>{};
              final byEmployeeCount = <String, int>{};

              for (final d in docs) {
                final data = d.data();
                // considera apenas done (se vier algo estranho no range)
                final st = statusFromString((data['status'] ?? 'done').toString());
                if (st != ApptStatus.done) continue;

                final services = (data['services'] as List?) ?? const [];
                final apptTotal = asInt(data['totalPrice'], def: calcTotalPrice(services));

                totalSold += apptTotal;
                totalCount += 1;

                final payment = data['payment'] is Map ? Map<String, dynamic>.from(data['payment']) : <String, dynamic>{};
                final paidAmount = asInt(payment['paidAmount']);
                totalPaid += paidAmount;

                // por serviço (valor)
                for (final s in services) {
                  if (s is! Map) continue;
                  final name = (s['name'] ?? '').toString().trim();
                  if (name.isEmpty) continue;
                  final price = asInt(s['price']);
                  byServiceValue[name] = (byServiceValue[name] ?? 0) + price;
                }

                // por funcionário (valor + qtd)
                final emp = (data['operatorName'] ?? 'Sem operador').toString();
                byEmployeeValue[emp] = (byEmployeeValue[emp] ?? 0) + apptTotal;
                byEmployeeCount[emp] = (byEmployeeCount[emp] ?? 0) + 1;
              }

              final totalOpen = (totalSold - totalPaid) < 0 ? 0 : (totalSold - totalPaid);

              // ordenações
              List<MapEntry<String, int>> topServices = byServiceValue.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              List<MapEntry<String, int>> topEmployees = byEmployeeValue.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NitroTile(icon: Icons.check_circle, title: 'Serviços finalizados (mês)', subtitle: '$totalCount'),
                  NitroTile(icon: Icons.attach_money, title: 'Vendido no mês', subtitle: brl(totalSold)),
                  NitroTile(icon: Icons.paid, title: 'Já pago', subtitle: brl(totalPaid)),
                  NitroTile(icon: Icons.payments_outlined, title: 'A receber', subtitle: brl(totalOpen)),

                  const SizedBox(height: 14),
                  const SectionTitle('Vendas por tipo de serviço (R\$)'),
                  const SizedBox(height: 10),
                  if (topServices.isEmpty)
                    Text('Sem dados ainda.', style: TextStyle(color: Colors.white.withOpacity(0.65)))
                  else
                    SimpleBarChart(
                      items: topServices.take(12).map((e) => ChartItem(e.key, e.value)).toList(),
                      valuePrefix: 'R\$ ',
                    ),

                  const SizedBox(height: 16),
                  const SectionTitle('Produtividade por funcionário (R\$)'),
                  const SizedBox(height: 10),
                  if (topEmployees.isEmpty)
                    Text('Sem dados ainda.', style: TextStyle(color: Colors.white.withOpacity(0.65)))
                  else ...[
                    SimpleBarChart(
                      items: topEmployees.take(10).map((e) => ChartItem(e.key, e.value)).toList(),
                      valuePrefix: 'R\$ ',
                    ),
                    const SizedBox(height: 10),
                    ...topEmployees.take(10).map((e) {
                      final qty = byEmployeeCount[e.key] ?? 0;
                      return NitroTile(
                        icon: Icons.person,
                        title: e.key,
                        subtitle: '${qty} serviços • ${brl(e.value)}',
                      );
                    }),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// =========================================================
/// OPS: Execução (Timer + Checklist Entrada + Checklist Saída)
/// - Entrada: KM + riscos + confirmar serviço
/// - Saída: KM + qualidade final
/// - Finalizar só se os dois estiverem completos
/// =========================================================
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
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _elapsed += 1));
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

  bool _isChecklistComplete(Map<String, dynamic> checklist, Iterable<String> keys) {
    for (final k in keys) {
      if (checklist[k] != true) return false;
    }
    return true;
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

  Future<void> _openCheckIn(BuildContext context, DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) async {
    final raw = data['checkIn'];
    final checkIn = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final itemsRaw = checkIn['items'];
    final items = itemsRaw is Map ? Map<String, dynamic>.from(itemsRaw) : <String, dynamic>{};

    final kmCtrl = TextEditingController(text: asInt(checkIn['km']).toString());
    bool confirmed = (checkIn['confirmedServices'] == true);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final doneCount = preChecklistItems.keys.where((k) => items[k] == true).length;

          return AlertDialog(
            backgroundColor: const Color(0xFF0F1724),
            title: Text('Entrada ($doneCount/${preChecklistItems.length})'),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: kmCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'KM de entrada', prefixIcon: Icon(Icons.speed)),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    value: confirmed,
                    onChanged: (v) => setLocal(() => confirmed = v),
                    title: const Text('Serviços confirmados com o cliente'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 10),
                  ...preChecklistItems.entries.map((e) {
                    final k = e.key;
                    final checked = items[k] == true;
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (v) => setLocal(() => items[k] = (v == true)),
                      title: Text(e.value),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () async {
                  await ref.set({
                    'checkIn': {
                      'km': int.tryParse(kmCtrl.text.trim()) ?? 0,
                      'confirmedServices': confirmed,
                      'items': items,
                      'createdAt': FieldValue.serverTimestamp(),
                    }
                  }, SetOptions(merge: true));

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entrada salva.')));
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

    kmCtrl.dispose();
  }

  Future<void> _openCheckOut(BuildContext context, DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) async {
    final raw = data['checkOut'];
    final checkOut = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final itemsRaw = checkOut['items'];
    final items = itemsRaw is Map ? Map<String, dynamic>.from(itemsRaw) : <String, dynamic>{};

    final kmCtrl = TextEditingController(text: asInt(checkOut['km']).toString());

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final doneCount = postChecklistItems.keys.where((k) => items[k] == true).length;

          return AlertDialog(
            backgroundColor: const Color(0xFF0F1724),
            title: Text('Saída ($doneCount/${postChecklistItems.length})'),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: kmCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'KM de saída', prefixIcon: Icon(Icons.speed)),
                  ),
                  const SizedBox(height: 12),
                  ...postChecklistItems.entries.map((e) {
                    final k = e.key;
                    final checked = items[k] == true;
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (v) => setLocal(() => items[k] = (v == true)),
                      title: Text(e.value),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () async {
                  await ref.set({
                    'checkOut': {
                      'km': int.tryParse(kmCtrl.text.trim()) ?? 0,
                      'items': items,
                      'createdAt': FieldValue.serverTimestamp(),
                    }
                  }, SetOptions(merge: true));

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saída salva.')));
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

    kmCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = apptsCol().doc(widget.apptId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const _LoadingPage(text: 'Carregando serviço...');

        final data = snap.data!.data() ?? {};

        final services = (data['services'] as List?) ?? const [];
        final service = servicesLabel(services);
        final totalPrice = asInt(data['totalPrice'], def: calcTotalPrice(services));

        final st = statusFromString((data['status'] ?? 'scheduled').toString());
        final ts = (data['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        final storedSeconds = asInt(data['workedSeconds']);

        if (_elapsed < storedSeconds) _elapsed = storedSeconds;

        final checkInRaw = data['checkIn'];
        final checkIn = checkInRaw is Map ? Map<String, dynamic>.from(checkInRaw) : <String, dynamic>{};
        final inItemsRaw = checkIn['items'];
        final inItems = inItemsRaw is Map ? Map<String, dynamic>.from(inItemsRaw) : <String, dynamic>{};

        final checkOutRaw = data['checkOut'];
        final checkOut = checkOutRaw is Map ? Map<String, dynamic>.from(checkOutRaw) : <String, dynamic>{};
        final outItemsRaw = checkOut['items'];
        final outItems = outItemsRaw is Map ? Map<String, dynamic>.from(outItemsRaw) : <String, dynamic>{};

        final kmIn = asInt(checkIn['km']);
        final kmOut = asInt(checkOut['km']);
        final confirmedServices = checkIn['confirmedServices'] == true;

        final preDone = _isChecklistComplete(inItems, preChecklistItems.keys);
        final postDone = _isChecklistComplete(outItems, postChecklistItems.keys);

        // aqui eu deixei KM obrigatório (do jeito que você pediu "KM só no checklist")
        final preReady = preDone && confirmedServices && kmIn > 0;
        final postReady = postDone && kmOut > 0;

        final canFinish = (st == ApptStatus.inProgress) && preReady && postReady;

        return Scaffold(
          appBar: AppBar(title: const Text('Execução do serviço')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              children: [
                TopHeader(
                  title: service.isEmpty ? 'Serviço' : service,
                  subtitle: 'Agendado: ${fmtDateTime(ts)}'
                      '${totalPrice > 0 ? " • ${brl(totalPrice)}" : ""}'
                      '${kmIn > 0 ? " • KM Ent: $kmIn" : ""}'
                      '${kmOut > 0 ? " • KM Sai: $kmOut" : ""}',
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
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tempo salvo.')));
                                }
                              }
                            : null,
                        child: const Text('Salvar'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                const SectionTitle('Checklist de entrada'),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: FilledButton.tonalIcon(
                    onPressed: st == ApptStatus.inProgress ? () => _openCheckIn(context, ref, data) : null,
                    icon: const Icon(Icons.rule),
                    label: Text(preReady ? 'Entrada completa ✅' : 'Abrir entrada (KM + confirmar)'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  preReady ? 'OK ✅' : 'Obrigatório: marcar itens + confirmar serviços + preencher KM entrada.',
                  style: TextStyle(color: Colors.white.withOpacity(0.65)),
                ),

                const SizedBox(height: 16),
                const SectionTitle('Checklist de saída'),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: FilledButton.tonalIcon(
                    onPressed: st == ApptStatus.inProgress ? () => _openCheckOut(context, ref, data) : null,
                    icon: const Icon(Icons.checklist),
                    label: Text(postReady ? 'Saída completa ✅' : 'Abrir saída (KM + qualidade)'),
                  ),
                ),

                const SizedBox(height: 16),
                const SectionTitle('Finalização'),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: canFinish
                        ? () async {
                            await ref.update({
                              'status': statusToString(ApptStatus.done),
                              'finishedAt': FieldValue.serverTimestamp(),
                              'workedSeconds': _elapsed,
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Serviço finalizado!')));
                              Navigator.pop(context);
                            }
                          }
                        : null,
                    icon: const Icon(Icons.check_circle),
                    label: Text(canFinish ? 'Finalizar serviço' : 'Complete entrada + saída'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// =========================================================
/// CHARTS (simples, sem libs)
/// =========================================================
class ChartItem {
  final String label;
  final int value;
  ChartItem(this.label, this.value);
}

class SimpleBarChart extends StatelessWidget {
  final List<ChartItem> items;
  final String valuePrefix;
  const SimpleBarChart({super.key, required this.items, this.valuePrefix = ''});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final maxV = items.map((e) => e.value).fold<int>(0, (a, b) => a > b ? a : b);
    return Column(
      children: items.map((e) {
        final pct = maxV <= 0 ? 0.0 : (e.value / maxV).clamp(0.0, 1.0);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF0F1724).withOpacity(0.92),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(e.label, style: const TextStyle(fontWeight: FontWeight.w900))),
                  Text('$valuePrefix${e.value}', style: TextStyle(color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 10,
                  backgroundColor: Colors.white.withOpacity(0.06),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}