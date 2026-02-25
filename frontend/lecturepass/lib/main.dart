import "dart:async";
import "dart:convert";

import "dart:math" show pi, sin, cos;
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:http/http.dart" as http;
import "package:web_socket_channel/web_socket_channel.dart";

void main() {
  runApp(const GamifyApp());
}

class AppColors {
  // Brand Colors
  static const Color primary = Color(0xFF6366F1); // Modern Blue/Indigo
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color accent = Color(0xFFF472B6); // Soft Pink/Accent
  static const Color secondary = Color(0xFF10B981); // Emerald Green
  
  // Neutral Colors
  static const Color background = Color(0xFF0F172A); // Slate 900
  static const Color surface = Color(0xFF1E293B); // Slate 800
  static const Color textBody = Color(0xFF94A3B8); // Slate 400
  static const Color textHeading = Color(0xFFF1F5F9); // Slate 100
  
  // Status Colors
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);
  
  // Game Board Colors
  static const Color boardIdle = Color(0xFF334155);
  static const Color boardTurn = Color(0xFF6366F1);
  static const Color boardEliminated = Color(0xFF991B1B);
  static const Color boardRemainIdle = Color(0xFF475569);
  
  // Gradients
  static const List<Color> primaryGradient = [Color(0xFF6366F1), Color(0xFFA855F7)];
  static const List<Color> surfaceGradient = [Color(0xFF1E293B), Color(0xFF0F172A)];
}

class GamifyApp extends StatelessWidget {
  const GamifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Bingo",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
          surface: AppColors.surface,
          onSurface: AppColors.textHeading,
          primary: AppColors.primary,
          secondary: AppColors.accent,
        ),
        scaffoldBackgroundColor: AppColors.background,
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(color: AppColors.textHeading, fontWeight: FontWeight.w800, fontSize: 32, letterSpacing: -0.5),
          headlineMedium: TextStyle(color: AppColors.textHeading, fontWeight: FontWeight.w700, fontSize: 24),
          titleMedium: TextStyle(color: AppColors.textHeading, fontWeight: FontWeight.w600, fontSize: 18),
          bodyMedium: TextStyle(color: AppColors.textBody, fontSize: 16),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.black12,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(width: 2, color: AppColors.primary),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          labelStyle: const TextStyle(color: AppColors.textBody),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

class Session {
  static String? accessToken;
  static String? username;
}

class ApiConfig {
  static String get _host => (kIsWeb || defaultTargetPlatform != TargetPlatform.android)
      ? "127.0.0.1"
      : "10.0.2.2";

  static String get baseUrl => "http://$_host:8000";
  static String get wsBase => "ws://$_host:8000";
}

class ApiClient {
  static Uri _uri(String path) => Uri.parse("${ApiConfig.baseUrl}$path");

  static Map<String, String> _headers({bool auth = false}) {
    final headers = <String, String>{"Content-Type": "application/json"};
    if (auth && Session.accessToken != null) {
      headers["Authorization"] = "Bearer ${Session.accessToken}";
    }
    return headers;
  }

  static Future<Map<String, dynamic>> register(String username, String password) async {
    final resp = await http.post(
      _uri("/register/"),
      headers: _headers(),
      body: jsonEncode({"username": username, "password": password}),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw Exception("Register failed");
  }

  static Future<void> login(String username, String password) async {
    final resp = await http.post(
      _uri("/login/"),
      headers: _headers(),
      body: jsonEncode({"username": username, "password": password}),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      Session.accessToken = data["access"] as String?;
      Session.username = username;
      return;
    }
    throw Exception("Login failed");
  }

  static Future<Map<String, dynamic>> getProfile() async {
    final resp = await http.get(_uri("/profile/"), headers: _headers(auth: true));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw Exception("Profile fetch failed");
  }

  static Future<Map<String, dynamic>> createRoom({int maxPlayers = 5, String gameType = "BINGO"}) async {
    final resp = await http.post(
      _uri("/rooms/create/"),
      headers: _headers(auth: true),
      body: jsonEncode({"max_players": maxPlayers, "game_type": gameType}),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw Exception("Create room failed");
  }

  static Future<Map<String, dynamic>> joinRoom(String roomId) async {
    final resp = await http.post(
      _uri("/rooms/join/"),
      headers: _headers(auth: true),
      body: jsonEncode({"room_id": roomId}),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw Exception("Join room failed");
  }

  static Future<List<dynamic>> getLeaderboard() async {
    final resp = await http.get(_uri("/leaderboard/"), headers: _headers(auth: true));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(resp.body) as List<dynamic>;
    }
    throw Exception("Leaderboard fetch failed");
  }
}

class AppShell extends StatelessWidget {
  const AppShell({required this.title, required this.child, this.actions = const [], super.key});

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
        actions: actions,
      ),
      body: Stack(
        children: [
          // Background Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)],
                  stops: [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),
          // Subtle Glow effects
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
            ),
          ),
          SafeArea(child: child),
        ],
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({required this.child, this.padding = const EdgeInsets.all(24), super.key});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ColorFilter.mode(Colors.black.withValues(alpha: 0.2), BlendMode.darken),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _doLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiClient.login(_username.text.trim(), _password.text.trim());
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
    } catch (_) {
      setState(() => _error = "Invalid credentials or server unavailable.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: "Gamify",
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Welcome Back", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textHeading)),
                  const SizedBox(height: 8),
                  const Text("Login to play multiplayer games with your friends.", style: TextStyle(color: AppColors.textBody)),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(labelText: "Username", prefixIcon: Icon(Icons.person_outline, color: AppColors.primary)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Password", prefixIcon: Icon(Icons.lock_outline, color: AppColors.primary)),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: const TextStyle(color: AppColors.error)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _doLogin,
                      child: _loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text("Login"),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RegisterPage()),
                      ),
                      child: RichText(
                        text: TextSpan(
                          text: "Don't have an account? ",
                          style: TextStyle(color: AppColors.textBody),
                          children: [
                            TextSpan(text: "Register", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _message;
  bool _isError = false;

  Future<void> _doRegister() async {
    setState(() {
      _loading = true;
      _message = null;
      _isError = false;
    });
    try {
      await ApiClient.register(_username.text.trim(), _password.text.trim());
      setState(() => _message = "Account created. You can login now.");
    } catch (_) {
      setState(() {
        _isError = true;
        _message = "Registration failed. Username may already exist.";
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: "Register",
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Create Account", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textHeading)),
                  const SizedBox(height: 8),
                  const Text("Join the arena and play with gamers worldwide.", style: TextStyle(color: AppColors.textBody)),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(labelText: "Username", prefixIcon: Icon(Icons.person_add_outlined, color: AppColors.primary)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Password", prefixIcon: Icon(Icons.lock_outline, color: AppColors.primary)),
                  ),
                  const SizedBox(height: 24),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_message!, style: TextStyle(color: _isError ? AppColors.error : AppColors.success)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _doRegister,
                      child: _loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text("Register"),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: RichText(
                        text: TextSpan(
                          text: "Already have an account? ",
                          style: TextStyle(color: AppColors.textBody),
                          children: [
                            TextSpan(text: "Login", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<dynamic>? _leaderboard;
  bool _loadingLeaderboard = true;
  String? _leaderboardError;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchLeaderboard();
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _fetchLeaderboard();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLeaderboard() async {
    try {
      final lb = await ApiClient.getLeaderboard();
      if (mounted) {
        setState(() {
          _leaderboard = lb;
          _loadingLeaderboard = false;
          _leaderboardError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingLeaderboard = false;
          _leaderboardError = "Leaderboard unavailable.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const cards = [
      ("Gamify", Icons.grid_4x4_rounded, true),
      ("Truth&Dare", Icons.quiz_rounded, true),
      ("OXO", Icons.close_rounded, true),
      ("Mini Golf", Icons.golf_course_rounded, true),
    ];

    return AppShell(
      title: "Home",
      actions: [
        IconButton(
          tooltip: "Profile",
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage())),
          icon: const Icon(Icons.person_outline_rounded, color: AppColors.textHeading),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Hello, ${Session.username ?? "Player"}",
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 4),
            const Text("Choose a game and start playing with friends.", style: TextStyle(color: AppColors.textBody)),
            const SizedBox(height: 24),
            SizedBox(
              height: 180,
              child: GridView.builder(
                itemCount: cards.length,
                scrollDirection: Axis.horizontal,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 1,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.8,
                ),
                itemBuilder: (context, index) {
                  final (title, icon, enabled) = cards[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      if (enabled) {
                        if (index == 0) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const GamifyRoomEntryPage()));
                        } else if (index == 1) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const TruthAndDarePage()));
                        } else if (index == 2) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const OXORoomEntryPage()));
                        } else if (index == 3) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const MiniGolfSplash()));
                        }
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: AppColors.surface,
                            content: Text("$title coming soon", style: const TextStyle(color: AppColors.textHeading)),
                          ),
                        );
                      }
                    },
                    child: Container(
                      width: 160,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: enabled
                              ? (index == 0
                                  ? [const Color(0xFF6366F1), const Color(0xFFA855F7)]
                                  : [const Color(0xFF3B82F6), const Color(0xFF2DD4BF)])
                              : [const Color(0xFF334155), const Color(0xFF1E293B)],
                        ),
                        boxShadow: enabled
                            ? [
                                BoxShadow(
                                  color: (index == 0 ? const Color(0xFF6366F1) : const Color(0xFF3B82F6)).withValues(alpha: 0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                )
                              ]
                            : [],
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            right: -20,
                            bottom: -20,
                            child: Icon(icon, size: 80, color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                                  child: Icon(icon, color: Colors.white, size: 24),
                                ),
                                const Spacer(),
                                Text(
                                  title,
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  enabled ? "Play Now" : "Locked",
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Text("Global Arena", style: Theme.of(context).textTheme.headlineMedium),
                const Spacer(),
                const Icon(Icons.leaderboard_rounded, color: Colors.amber, size: 20),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loadingLeaderboard
                  ? const Center(child: CircularProgressIndicator())
                  : _leaderboardError != null
                      ? Center(child: Text(_leaderboardError!, style: const TextStyle(color: AppColors.error)))
                      : _leaderboard == null || _leaderboard!.isEmpty
                          ? const Center(child: Text("No legends found yet."))
                      : ListView.builder(
                          itemCount: _leaderboard!.length,
                          itemBuilder: (context, index) {
                            final p = _leaderboard![index];
                            final rank = index + 1;
                            final username = p["username"] ?? "Player";
                            final points = p["points"] ?? 0;
                            final winRate = p["win_rate"] ?? 0.0;
                            final wins = p["wins"] ?? 0;
                            final total = p["total_matches"] ?? 0;
                            final isMe = username == Session.username;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: GlassCard(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: rank <= 3 ? Colors.amber.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          "$rank",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: rank <= 3 ? Colors.amber : AppColors.textBody,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            username,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: isMe ? AppColors.primaryLight : AppColors.textHeading,
                                            ),
                                          ),
                                          Text(
                                            "$wins Wins / $total Matches",
                                            style: const TextStyle(color: AppColors.textBody, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          "$points PTS",
                                          style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.secondary, fontSize: 16),
                                        ),
                                        Text(
                                          "$winRate% Win Rate",
                                          style: const TextStyle(color: AppColors.textBody, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _profile;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.getProfile();
      if (!mounted) return;
      setState(() => _profile = data);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Could not load profile.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: "Profile",
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: _error != null
            ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
            : _profile == null
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GlassCard(
                        padding: const EdgeInsets.all(28),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                              child: Text(
                                (Session.username ?? "P")[0].toUpperCase(),
                                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.primaryLight),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(Session.username ?? "Player",
                                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textHeading)),
                                  const SizedBox(height: 4),
                                  const Text("Elite Gamer | Level 12", style: TextStyle(color: AppColors.textBody)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text("Statistics", style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 16),
                      Expanded(
                        child: GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.5,
                          children: [
                            _statTile("Matches", "${_profile!["total_matches"] ?? 0}", Icons.sports_esports_outlined),
                            _statTile("Wins", "${_profile!["wins"] ?? 0}", Icons.emoji_events_outlined),
                            _statTile("Win Rate", "${_profile!["win_rate"] ?? 0}%", Icons.insights_outlined),
                            _statTile("Points", "${_profile!["points"] ?? 0}", Icons.stars_outlined),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primaryLight),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: AppColors.textBody, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.textHeading)),
        ],
      ),
    );
  }
}

class GamifyRoomEntryPage extends StatefulWidget {
  const GamifyRoomEntryPage({super.key});

  @override
  State<GamifyRoomEntryPage> createState() => _GamifyRoomEntryPageState();
}

class _GamifyRoomEntryPageState extends State<GamifyRoomEntryPage> {
  final _roomId = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _createRoom() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final room = await ApiClient.createRoom();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WaitingRoomPage(roomId: room["room_id"] as String, isOwner: true)),
      );
    } catch (_) {
      setState(() => _error = "Could not create room.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinRoom() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final room = await ApiClient.joinRoom(_roomId.text.trim().toUpperCase());
      if (!mounted) return;
      final ownerUsername = room["owner_username"] as String?;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WaitingRoomPage(
            roomId: room["room_id"] as String,
            isOwner: ownerUsername == Session.username,
          ),
        ),
      );
    } catch (_) {
      setState(() => _error = "Could not join room.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: "Bingo Room",
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Lobby Arena", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textHeading)),
                  const SizedBox(height: 8),
                  const Text("Host a new game or join an existing arena.", style: TextStyle(color: AppColors.textBody)),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: AppColors.primaryGradient),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _createRoom,
                        style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        label: const Text("Create New Arena"),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.1))),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text("OR JOIN", style: TextStyle(color: AppColors.textBody, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      ),
                      Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.1))),
                    ],
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _roomId,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 4),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: "ENTER ROOM ID",
                      hintText: "AAAAAA",
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _joinRoom,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        side: const BorderSide(color: AppColors.primary, width: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        foregroundColor: AppColors.primaryLight,
                      ),
                      icon: const Icon(Icons.login_rounded),
                      label: const Text("Join Arena", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Center(child: Text(_error!, style: const TextStyle(color: AppColors.error))),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WaitingRoomPage extends StatefulWidget {
  const WaitingRoomPage({required this.roomId, required this.isOwner, super.key});

  final String roomId;
  final bool isOwner;

  @override
  State<WaitingRoomPage> createState() => _WaitingRoomPageState();
}

class _WaitingRoomPageState extends State<WaitingRoomPage> {
  Map<String, dynamic>? _room;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  void _connect() {
    final token = Session.accessToken ?? "";
    final uri = Uri.parse("${ApiConfig.wsBase}/ws/gamify/${widget.roomId}/?token=$token");
    _channel = WebSocketChannel.connect(uri);
    _sub = _channel!.stream.listen(_onMessage, onError: (_) => setState(() => _error = "WebSocket connection error"));
    _channel!.sink.add(jsonEncode({"action": "room_state"}));
  }

  void _onMessage(dynamic raw) {
    final data = jsonDecode(raw as String) as Map<String, dynamic>;
    if (data["type"] == "error") {
      setState(() => _error = data["message"]?.toString());
      return;
    }
    final roomData = data["data"] as Map<String, dynamic>?;
    if (roomData == null) return;
    setState(() => _room = roomData);
    if (roomData["status"] == "STARTED") {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GamifyGamePage(roomId: widget.roomId, initialRoomData: roomData),
        ),
      );
    }
  }

  void _startGame() {
    _channel?.sink.add(jsonEncode({"action": "start_game"}));
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final players = (room?["players"] as List<dynamic>? ?? []);
    return AppShell(
      title: "Waiting Room ${widget.roomId}",
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.groups_rounded),
                    const SizedBox(width: 10),
                    Text("Players ${players.length}/${room?["max_players"] ?? 5}",
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text("Status: ${room?["status"] ?? "WAITING"}"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: players.length,
                itemBuilder: (context, index) {
                  final p = players[index] as Map<String, dynamic>;
                  final owner = p["username"]?.toString() == room?["owner_username"]?.toString();
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text("${p["turn_order"]}")),
                      title: Text(p["username"]?.toString() ?? "Player"),
                      subtitle: Text(owner ? "Room owner" : "Player"),
                    ),
                  );
                },
              ),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            if (widget.isOwner)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: players.length < 2 ? null : _startGame,
                  child: const Text("Start Game"),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text("Waiting for owner to start the game..."),
              ),
          ],
        ),
      ),
    );
  }
}
class GamifyGamePage extends StatefulWidget {
  const GamifyGamePage({required this.roomId, required this.initialRoomData, super.key});

  final String roomId;
  final Map<String, dynamic> initialRoomData;

  @override
  State<GamifyGamePage> createState() => _GamifyGamePageState();
}

class _GamifyGamePageState extends State<GamifyGamePage> {
  late Map<String, dynamic> _room;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _ticker;
  int _secondsLeft = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _room = widget.initialRoomData;
    _connect();
    _startTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  void _connect() {
    final token = Session.accessToken ?? "";
    final uri = Uri.parse("${ApiConfig.wsBase}/ws/gamify/${widget.roomId}/?token=$token");
    _channel = WebSocketChannel.connect(uri);
    _sub = _channel!.stream.listen(_onMessage, onError: (_) => setState(() => _error = "WebSocket connection error"));
    _channel!.sink.add(jsonEncode({"action": "room_state"}));
  }

  void _onMessage(dynamic raw) {
    final data = jsonDecode(raw as String) as Map<String, dynamic>;
    if (data["type"] == "error") {
      setState(() => _error = data["message"]?.toString());
      return;
    }
    final roomData = data["data"] as Map<String, dynamic>?;
    if (roomData == null) return;
    setState(() => _room = roomData);
    _syncTimer();
    if (roomData["status"] == "ENDED") {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ResultPage(roomData: roomData)));
    }
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _syncTimer());
  }

  void _syncTimer() {
    final deadlineRaw = _room["turn_deadline"]?.toString();
    if (deadlineRaw == null || deadlineRaw.isEmpty) {
      setState(() => _secondsLeft = 0);
      return;
    }
    final deadline = DateTime.tryParse(deadlineRaw)?.toLocal();
    if (deadline == null) {
      setState(() => _secondsLeft = 0);
      return;
    }
    final left = deadline.difference(DateTime.now()).inSeconds;
    setState(() => _secondsLeft = left > 0 ? left : 0);
  }

  List<int> _myBoard() {
    final players = (_room["players"] as List<dynamic>? ?? []);
    for (final p in players) {
      final map = p as Map<String, dynamic>;
      if (map["username"] == Session.username) {
        final board = (map["board_numbers"] as List<dynamic>? ?? []).cast<int>();
        if (board.length == 25) return board;
      }
    }
    return List<int>.generate(25, (i) => i + 1);
  }

  void _markNumber(int n) {
    _channel?.sink.add(jsonEncode({"action": "mark_number", "number": n}));
  }

  @override
  Widget build(BuildContext context) {
    final called = (_room["called_numbers"] as List<dynamic>? ?? []).cast<int>().toSet();
    final players = (_room["players"] as List<dynamic>? ?? []);
    final board = _myBoard();
    final turnUsername = _room["current_turn_username"]?.toString() ?? "-";
    final myTurn = turnUsername == Session.username;

    return AppShell(
      title: "Bingo ${widget.roomId}",
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Current Turn", style: TextStyle(color: AppColors.textBody, fontSize: 12, fontWeight: FontWeight.bold)),
                      Text(turnUsername, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textHeading)),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: myTurn ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: myTurn ? AppColors.primary : Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 18, color: myTurn ? AppColors.primaryLight : AppColors.textBody),
                        const SizedBox(width: 8),
                        Text("$_secondsLeft", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: myTurn ? AppColors.primaryLight : AppColors.textHeading)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: myTurn ? AppColors.primary.withValues(alpha: 0.5) : Colors.white10,
                    width: myTurn ? 2 : 1,
                  ),
                  boxShadow: myTurn
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ]
                      : [],
                ),
                child: GridView.builder(
                  itemCount: board.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.0,
                  ),
                  itemBuilder: (context, index) {
                    final n = board[index];
                    final marked = called.contains(n);
                    final tileColor = marked
                        ? AppColors.boardEliminated
                        : (myTurn ? AppColors.primary : AppColors.boardIdle);
                    
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: (myTurn && !marked) ? () => _markNumber(n) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: tileColor,
                          boxShadow: (myTurn && !marked) 
                            ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))] 
                            : [],
                          gradient: marked 
                            ? const LinearGradient(colors: [Color(0xFF991B1B), Color(0xFF7F1D1D)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                            : (myTurn ? const LinearGradient(colors: AppColors.primaryGradient) : null),
                        ),
                        child: Center(
                          child: Text(
                            "$n",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              decoration: marked ? TextDecoration.lineThrough : TextDecoration.none,
                              decorationThickness: 3,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text("Participants", style: TextStyle(color: AppColors.textHeading, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              child: ListView.builder(
                itemCount: players.length,
                itemBuilder: (context, index) {
                  final p = players[index] as Map<String, dynamic>;
                  final isMe = p["username"] == Session.username;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isMe ? AppColors.primary.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isMe ? AppColors.primary.withValues(alpha: 0.3) : Colors.transparent),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: p["status"] == "READY" ? AppColors.secondary : AppColors.textBody,
                        child: Text("${index + 1}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      title: Text(p["username"]?.toString() ?? "Player", style: TextStyle(fontWeight: FontWeight.bold, color: isMe ? AppColors.primaryLight : AppColors.textHeading)),
                      subtitle: Text("Lines: ${p["lines_completed"]} | ${p["status"]}", style: const TextStyle(fontSize: 11)),
                      trailing: p["rank"] != null ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: Color(0xFFFFD700), shape: BoxShape.circle),
                        child: Text("${p["rank"]}", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ) : null,
                    ),
                  );
                },
              ),
            ),
            if (_error != null) 
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(child: Text(_error!, style: const TextStyle(color: AppColors.error))),
              ),
          ],
        ),
      ),
    );
  }
}

class ResultPage extends StatelessWidget {
  const ResultPage({required this.roomData, super.key});

  final Map<String, dynamic> roomData;

  @override
  Widget build(BuildContext context) {
    final players = (roomData["players"] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    players.sort((a, b) => ((a["rank"] as int?) ?? 999).compareTo((b["rank"] as int?) ?? 999));

    return AppShell(
      title: "Battle Summary",
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.emoji_events_rounded, size: 80, color: Colors.amber),
            const SizedBox(height: 16),
            const Text("Battle Results", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.textHeading)),
            const SizedBox(height: 32),
            Expanded(
              child: ListView.builder(
                itemCount: players.length,
                itemBuilder: (context, index) {
                  final p = players[index];
                  final rank = (p["rank"] as int?) ?? (index + 1);
                  final isWinner = rank == 1;
                  final points = rank == 1 ? "+10 XP" : rank == 2 ? "+5 XP" : "0 XP";
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isWinner ? Colors.amber.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text("$rank", style: TextStyle(fontWeight: FontWeight.bold, color: isWinner ? Colors.amber : Colors.white)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p["username"] ?? "Player", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                Text("${p["lines_completed"]} lines cleared", style: const TextStyle(color: AppColors.textBody, fontSize: 13)),
                              ],
                            ),
                          ),
                          Text(points, style: TextStyle(fontWeight: FontWeight.w900, color: isWinner ? AppColors.secondary : AppColors.textBody)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const HomePage()),
                  (_) => false,
                ),
                child: const Text("Return to HQ"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TruthAndDarePage extends StatefulWidget {
  const TruthAndDarePage({super.key});

  @override
  State<TruthAndDarePage> createState() => _TruthAndDarePageState();
}

class _TruthAndDarePageState extends State<TruthAndDarePage> {
  final _nameController = TextEditingController();
  final List<String> _players = [];

  void _addPlayer() {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      setState(() {
        _players.add(name);
        _nameController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: "Add Players",
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            GlassCard(
              child: Column(
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: "Player Name",
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add_circle, color: AppColors.primary),
                        onPressed: _addPlayer,
                      ),
                    ),
                    onSubmitted: (_) => _addPlayer(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: _players.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                            child: Text("${index + 1}", style: const TextStyle(color: AppColors.primaryLight)),
                          ),
                          const SizedBox(width: 16),
                          Text(_players[index], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.error),
                            onPressed: () => setState(() => _players.removeAt(index)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _players.length < 2
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => TruthAndDareGamePage(players: _players)),
                        );
                      },
                child: const Text("Start Game"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TruthAndDareGamePage extends StatefulWidget {
  const TruthAndDareGamePage({required this.players, super.key});
  final List<String> players;

  @override
  State<TruthAndDareGamePage> createState() => _TruthAndDareGamePageState();
}

class _TruthAndDareGamePageState extends State<TruthAndDareGamePage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _currentRotation = 0;
  String? _selectedPlayer;
  bool _spinning = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 5));
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart);
    
    _controller.addListener(() {
      setState(() {
        // Total rotation = start + (spin_distance * animated_value)
        _currentRotation = _baseRotation + (_spinDistance * _animation.value);
      });
    });
  }

  double _baseRotation = 0;
  double _spinDistance = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _spin() {
    if (_spinning) return;
    
    final randomIdx = (DateTime.now().millisecondsSinceEpoch % widget.players.length);
    final anglePerPlayer = (2 * pi) / widget.players.length;
    // We want the bottle tip (which is currently up at -pi/2) to point at the player
    // The player 'i' is at angle (i * 2*pi/total)
    // So the bottle rotation should be (i * 2*pi/total)
    final targetAngle = anglePerPlayer * randomIdx;

    const loops = 8;
    setState(() {
      _spinning = true;
      _selectedPlayer = null;
      _baseRotation = _currentRotation % (2 * pi);
      // Distance to move = loops + target offset from base
      _spinDistance = (loops * 2 * pi) + (targetAngle - _baseRotation);
    });

    _controller.forward(from: 0).then((_) {
      setState(() {
        _spinning = false;
        _selectedPlayer = widget.players[randomIdx];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: "Battle Arena",
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Exit", style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
        ),
      ],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 400,
              width: 400,
              child: Stack(
                alignment: Alignment.center,
                children: [
                   // Glowing Background behind bottle
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          blurRadius: 100,
                          spreadRadius: 20,
                        )
                      ],
                    ),
                  ),
                  
                  for (int i = 0; i < widget.players.length; i++)
                    _buildPlayerNode(i),

                  Transform.rotate(
                    angle: _currentRotation,
                    child: const BottleWidget(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            if (_selectedPlayer != null)
              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                child: Column(
                  children: [
                    const Text("The Bottle Chose...", style: TextStyle(color: AppColors.textBody, fontSize: 14)),
                    const SizedBox(height: 8),
                    Text(
                      _selectedPlayer!,
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.amber),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: 220,
              height: 60,
              child: FilledButton(
                onPressed: _spinning ? null : _spin,
                style: FilledButton.styleFrom(
                  elevation: 8,
                  shadowColor: AppColors.primary.withValues(alpha: 0.4),
                ),
                child: Text(
                  _spinning ? "THE BOTTLE SPINS..." : "SPIN BOTTLE",
                  style: const TextStyle(letterSpacing: 1.2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerNode(int index) {
    final total = widget.players.length;
    final angle = (2 * pi / total) * index;
    const radius = 150.0;
    
    return Transform.translate(
      offset: Offset(radius * sin(angle), -radius * cos(angle)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.surface.withValues(alpha: 0.95), AppColors.background.withValues(alpha: 0.9)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))
          ],
        ),
        child: Text(
          widget.players[index],
          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }
}

class BottleWidget extends StatelessWidget {
  const BottleWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      "assets/wine.png",
      height: 180,
      fit: BoxFit.contain,
    );
  }
}



class OXORoomEntryPage extends StatefulWidget {
  const OXORoomEntryPage({super.key});

  @override
  State<OXORoomEntryPage> createState() => _OXORoomEntryPageState();
}

class _OXORoomEntryPageState extends State<OXORoomEntryPage> {
  final _roomIdController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _createRoom() async {
    setState(() => _loading = true);
    try {
      final room = await ApiClient.createRoom(maxPlayers: 2, gameType: "OXO");
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => OXOGamePage(roomId: room["room_id"])));
    } catch (e) {
      setState(() => _error = "Failed to create room.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinRoom() async {
    final rid = _roomIdController.text.trim().toUpperCase();
    if (rid.isEmpty) return;
    setState(() => _loading = true);
    try {
      final room = await ApiClient.joinRoom(rid);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => OXOGamePage(roomId: room["room_id"])));
    } catch (e) {
      setState(() => _error = "Failed to join room. Check ID.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: "OXO Arena",
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: GlassCard(
              child: Column(
                children: [
                  const Icon(Icons.close_rounded, size: 60, color: AppColors.primaryLight),
                  const SizedBox(height: 16),
                  const Text("1 vs 1 Tic-Tac-Toe", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _createRoom,
                      icon: const Icon(Icons.add_box_rounded),
                      label: const Text("Create Room"),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: Colors.white24)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text("OR JOIN", style: TextStyle(color: AppColors.textBody, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const Expanded(child: Divider(color: Colors.white24)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _roomIdController,
                    decoration: const InputDecoration(labelText: "Room ID", hintText: "Enter 6-char ID"),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _loading ? null : _joinRoom,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("Join Room", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OXOGamePage extends StatefulWidget {
  const OXOGamePage({required this.roomId, super.key});
  final String roomId;

  @override
  State<OXOGamePage> createState() => _OXOGamePageState();
}

class _OXOGamePageState extends State<OXOGamePage> {
  WebSocketChannel? _channel;
  Map<String, dynamic>? _room;
  String? _error;
  Timer? _timer;
  int _secondsLeft = 30;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    final wsUrl = "${ApiConfig.wsBase.replaceFirst("http", "ws")}/ws/oxo/${widget.roomId}/?token=${Session.accessToken}";
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _channel!.stream.listen(_onMessage, onError: _onError, onDone: _onDone);
  }

  void _onMessage(dynamic message) {
    final data = jsonDecode(message as String);
    if (data["type"] == "room_snapshot" || data["type"] == "game_started" || data["type"] == "turn_changed" || data["type"] == "turn_auto_skipped" || data["type"] == "game_ended") {
      setState(() {
        _room = data["data"];
        _error = null;
        _startTimer();
      });
    } else if (data["type"] == "error") {
      setState(() => _error = data["message"]);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (_room?["status"] == "STARTED" && _room?["turn_deadline"] != null) {
      final deadline = DateTime.parse(_room!["turn_deadline"]).toLocal();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final now = DateTime.now();
        final diff = deadline.difference(now).inSeconds;
        setState(() {
          _secondsLeft = diff < 0 ? 0 : diff;
        });
        if (diff <= 0) timer.cancel();
      });
    }
  }

  void _onError(e) => setState(() => _error = "Connection lost.");
  void _onDone() => setState(() => _error = "Disconnected.");

  void _startGame() {
    _channel?.sink.add(jsonEncode({"action": "start_game"}));
  }

  void _makeMove(int index) {
    _channel?.sink.add(jsonEncode({"action": "mark_number", "number": index}));
  }

  void _rematch() {
    _channel?.sink.add(jsonEncode({"action": "rematch"}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return AppShell(title: "OXO", child: Center(child: Text(_error!, style: const TextStyle(color: AppColors.error))));
    }
    if (_room == null) {
      return const AppShell(title: "OXO", child: Center(child: CircularProgressIndicator()));
    }

    // Fixed owner check: check if owner's user_id matches Session user id? 
    // Actually using username is safer if user_id isn't easily available in Session.
    final isOwner = _room!["owner_username"] == Session.username;
    final status = _room!["status"];
    final players = _room!["players"] as List;
    final board = _room!["called_numbers"] as List; // This is our 3x3 board in OXO

    return AppShell(
      title: "Room: ${widget.roomId}",
      actions: [
         if (status == "ENDED")
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Exit", style: TextStyle(color: AppColors.error))),
      ],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: players.map((p) {
                final isCurrent = _room!["current_turn_player_id"] == p["user_id"];
                final isWinner = (_room!["winner_order"] as List).contains(p["user_id"]);
                final color = isCurrent ? AppColors.primary : (isWinner ? AppColors.secondary : Colors.white24);
                return Column(
                  children: [
                    CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.2),
                      child: Text(p["turn_order"] == 1 ? "X" : "O", style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 4),
                    Text(p["username"], style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                  ],
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            if (status == "STARTED")
              Text("Time Left: $_secondsLeft s", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.accent)),
            const SizedBox(height: 24),
            Expanded(
              child: status == "WAITING"
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Waiting for players...", style: TextStyle(fontSize: 18)),
                          const SizedBox(height: 16),
                          if (isOwner && players.length == 2)
                            FilledButton(onPressed: _startGame, child: const Text("Start Battle")),
                        ],
                      ),
                    )
                  : GridView.builder(
                      itemCount: 9,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12),
                      itemBuilder: (context, index) {
                        final val = board[index];
                        final isMyTurn = _room!["current_turn_player_id"] != null && _room!["current_turn_username"] == Session.username;
                        
                        String display = "";
                        Color? color;
                        if (val != null) {
                           // Find which player this user_id belongs to
                           final pIdx = players.indexWhere((p) => p["user_id"] == val);
                           display = pIdx == 0 ? "X" : "O";
                           color = pIdx == 0 ? AppColors.primaryLight : AppColors.accent;
                        }

                        return InkWell(
                          onTap: (status == "STARTED" && isMyTurn && val == null) ? () => _makeMove(index) : null,
                          child: GlassCard(
                            padding: EdgeInsets.zero,
                            child: Center(
                              child: Text(display, style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: color)),
                            ),
                          ),
                        );
                      },
                    ),
            ),
             if (status == "ENDED")
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: GlassCard(
                  child: Column(
                    children: [
                      Text(
                        _room!["winner_order"].isEmpty ? "It's a Draw!" : "${players.firstWhere((p) => p["user_id"] == _room!["winner_order"][0])["username"]} Wins!",
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _rematch,
                        child: const Text("Play Again"),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// MINI GOLF GAME
// -----------------------------------------------------------------------------

class GameLevel {
  final Offset ballStart;
  final Offset holePos;
  final List<Rect> obstacles;

  const GameLevel({
    required this.ballStart,
    required this.holePos,
    this.obstacles = const [],
  });
}

class MiniGolfLevels {
  static const List<GameLevel> levels = [
    // Level 1: Basic
    GameLevel(
      ballStart: Offset(200, 600),
      holePos: Offset(200, 150),
    ),
    // Level 2: One center obstacle
    GameLevel(
      ballStart: Offset(200, 600),
      holePos: Offset(200, 150),
      obstacles: [Rect.fromLTWH(100, 350, 200, 20)],
    ),
    // Level 3: Two side obstacles
    GameLevel(
      ballStart: Offset(200, 600),
      holePos: Offset(200, 100),
      obstacles: [
        Rect.fromLTWH(50, 300, 120, 20),
        Rect.fromLTWH(230, 400, 120, 20),
      ],
    ),
    // Level 4: Narrow passage
    GameLevel(
      ballStart: Offset(200, 650),
      holePos: Offset(200, 50),
      obstacles: [
        Rect.fromLTWH(0, 300, 150, 20),
        Rect.fromLTWH(250, 300, 150, 20),
      ],
    ),
    // Level 5: Diagonal walls
    GameLevel(
      ballStart: Offset(50, 650),
      holePos: Offset(350, 100),
      obstacles: [
        Rect.fromLTWH(0, 400, 250, 20),
        Rect.fromLTWH(150, 250, 250, 20),
      ],
    ),
     // Level 6: Box in center
    GameLevel(
      ballStart: Offset(200, 650),
      holePos: Offset(200, 200),
      obstacles: [
        Rect.fromLTWH(150, 350, 100, 100),
      ],
    ),
    // Level 7: Multiple small blocks
    GameLevel(
      ballStart: Offset(200, 650),
      holePos: Offset(200, 100),
      obstacles: [
        Rect.fromLTWH(100, 500, 50, 50),
        Rect.fromLTWH(250, 500, 50, 50),
        Rect.fromLTWH(175, 300, 50, 50),
      ],
    ),
    // Level 8: Maze-like
    GameLevel(
      ballStart: Offset(50, 650),
      holePos: Offset(350, 50),
      obstacles: [
        Rect.fromLTWH(0, 500, 300, 20),
        Rect.fromLTWH(100, 350, 300, 20),
        Rect.fromLTWH(0, 200, 300, 20),
      ],
    ),
    // Level 9: Slalom
    GameLevel(
      ballStart: Offset(200, 650),
      holePos: Offset(200, 50),
      obstacles: [
        Rect.fromLTWH(50, 550, 300, 20),
        Rect.fromLTWH(50, 450, 300, 20),
        Rect.fromLTWH(50, 350, 300, 20),
        Rect.fromLTWH(50, 250, 300, 20),
        Rect.fromLTWH(50, 150, 300, 20),
      ],
    ),
    // Level 10: Final Challenge
    GameLevel(
      ballStart: Offset(200, 650),
      holePos: Offset(200, 80),
      obstacles: [
        Rect.fromLTWH(80, 200, 240, 20),
        Rect.fromLTWH(80, 200, 20, 300),
        Rect.fromLTWH(300, 200, 20, 300),
        Rect.fromLTWH(180, 400, 40, 40),
      ],
    ),
  ];
}

class MiniGolfSplash extends StatefulWidget {
  const MiniGolfSplash({super.key});

  @override
  State<MiniGolfSplash> createState() => _MiniGolfSplashState();
}

class _MiniGolfSplashState extends State<MiniGolfSplash> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MiniGolfHome()));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: "Mini Golf",
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.golf_course_rounded, size: 100, color: AppColors.primary),
            const SizedBox(height: 24),
            Text("Ready Set Golf", style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 16),
            const CircularProgressIndicator(color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class MiniGolfHome extends StatelessWidget {
  const MiniGolfHome({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: "Mini Golf",
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sports_golf_rounded, size: 80, color: AppColors.secondary),
                const SizedBox(height: 24),
                const Text("Mini Golf Practice", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textHeading)),
                const SizedBox(height: 12),
                const Text(
                  "Drag to aim and shoot.\nComplete 10 levels of increasing difficulty!",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textBody),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MiniGolfGamePage())),
                    child: const Text("Start Practice"),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Back to Home", style: TextStyle(color: AppColors.textBody)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MiniGolfGamePage extends StatefulWidget {
  const MiniGolfGamePage({super.key});

  @override
  State<MiniGolfGamePage> createState() => _MiniGolfGamePageState();
}

class _MiniGolfGamePageState extends State<MiniGolfGamePage> with SingleTickerProviderStateMixin {
  // Game state
  late Offset ballPos;
  Offset ballVel = Offset.zero;
  int strokes = 0;
  int timeLeft = 30;
  Timer? gameTimer;
  late Ticker physicsTicker;

  // Level state
  int currentLevelIndex = 0;
  late Offset holePos;
  List<Rect> obstacles = [];

  // Drag state
  Offset? dragStart;
  Offset? dragCurrent;

  // Physics constants
  final double ballRadius = 12.0;
  final double holeRadius = 20.0;
  final double friction = 0.985;
  final double minStopSpeed = 0.5;

  bool isGameOver = false;

  @override
  void initState() {
    super.initState();
    _loadLevel(0);
    physicsTicker = createTicker(_updatePhysics);
    physicsTicker.start();
    _startTimer();
  }

  void _loadLevel(int index) {
    if (index >= MiniGolfLevels.levels.length) {
      _winGame(totalFinish: true);
      return;
    }
    final level = MiniGolfLevels.levels[index];
    setState(() {
      currentLevelIndex = index;
      ballPos = level.ballStart;
      holePos = level.holePos;
      obstacles = level.obstacles;
      ballVel = Offset.zero;
      strokes = 0;
      timeLeft = 30;
      isGameOver = false;
    });
  }

  void _startTimer() {
    gameTimer?.cancel();
    gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (timeLeft > 0) {
            timeLeft--;
          } else {
            _gameOver();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    gameTimer?.cancel();
    physicsTicker.dispose();
    super.dispose();
  }

  void _updatePhysics(Duration elapsed) {
    if (isGameOver) return;

    setState(() {
      // Apply velocity
      ballPos += ballVel;

      // Apply friction
      ballVel *= friction;

      // Stop if slow
      if (ballVel.distance < minStopSpeed) {
        ballVel = Offset.zero;
      }

      // Boundary collision
      final size = MediaQuery.of(context).size;
      const margin = 20.0;
      final topBoundary = margin; 
      final bottomBoundary = size.height - margin - 140; // Approx adjustment for AppBar and HUD

      if (ballPos.dx - ballRadius < margin) {
        ballPos = Offset(margin + ballRadius, ballPos.dy);
        ballVel = Offset(-ballVel.dx * 0.8, ballVel.dy);
      } else if (ballPos.dx + ballRadius > size.width - margin) {
        ballPos = Offset(size.width - margin - ballRadius, ballPos.dy);
        ballVel = Offset(-ballVel.dx * 0.8, ballVel.dy);
      }

      if (ballPos.dy - ballRadius < topBoundary) {
        ballPos = Offset(ballPos.dx, topBoundary + ballRadius);
        ballVel = Offset(ballVel.dx, -ballVel.dy * 0.8);
      } else if (ballPos.dy + ballRadius > bottomBoundary) {
        ballPos = Offset(ballPos.dx, bottomBoundary - ballRadius);
        ballVel = Offset(ballVel.dx, -ballVel.dy * 0.8);
      }

      // Obstacle collision
      for (final rect in obstacles) {
        if (rect.inflate(ballRadius).contains(ballPos)) {
          // Determine which side was hit
          final dx1 = (ballPos.dx - rect.left).abs();
          final dx2 = (ballPos.dx - rect.right).abs();
          final dy1 = (ballPos.dy - rect.top).abs();
          final dy2 = (ballPos.dy - rect.bottom).abs();

          final min = [dx1, dx2, dy1, dy2].reduce((a, b) => a < b ? a : b);

          if (min == dx1 || min == dx2) {
            ballVel = Offset(-ballVel.dx * 0.8, ballVel.dy);
            ballPos = Offset(min == dx1 ? rect.left - ballRadius : rect.right + ballRadius, ballPos.dy);
          } else {
            ballVel = Offset(ballVel.dx, -ballVel.dy * 0.8);
            ballPos = Offset(ballPos.dx, min == dy1 ? rect.top - ballRadius : rect.bottom + ballRadius);
          }
        }
      }

      // Hole collision detection
      final distToHole = (ballPos - holePos).distance;
      if (distToHole < holeRadius) {
        if (currentLevelIndex < MiniGolfLevels.levels.length - 1) {
          _nextLevel();
        } else {
          _winGame(totalFinish: true);
        }
      }
    });
  }

  void _nextLevel() {
    _loadLevel(currentLevelIndex + 1);
  }

  void _winGame({bool totalFinish = false}) {
    if (isGameOver) return;
    isGameOver = true;
    physicsTicker.stop();
    gameTimer?.cancel();
    final score = (100 - strokes * 5) + timeLeft;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MiniGolfScoreScreen(score: score, strokes: strokes, timeLeft: timeLeft)));
  }

  void _gameOver() {
    if (isGameOver) return;
    isGameOver = true;
    physicsTicker.stop();
    gameTimer?.cancel();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MiniGolfGameOverScreen()));
  }

  void _resetBall() {
    _loadLevel(currentLevelIndex);
    _startTimer();
    if (!physicsTicker.isActive) physicsTicker.start();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: "Level ${currentLevelIndex + 1}",
      actions: [
        IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _resetBall),
      ],
      child: GestureDetector(
        onPanStart: (details) {
          if (ballVel == Offset.zero && !isGameOver) {
            dragStart = details.localPosition;
          }
        },
        onPanUpdate: (details) {
          if (dragStart != null) {
            setState(() {
              dragCurrent = details.localPosition;
            });
          }
        },
        onPanEnd: (details) {
          if (dragStart != null && dragCurrent != null) {
            final dragVector = dragStart! - dragCurrent!;
            if (dragVector.distance > 0.1) {
              final power = dragVector.distance.clamp(0.0, 150.0) / 10.0;
              final direction = dragVector / dragVector.distance;

              setState(() {
                ballVel = direction * power;
                strokes++;
              });
            }
          }
          setState(() {
            dragStart = null;
            dragCurrent = null;
          });
        },
        child: Container(
          color: Colors.transparent, // Capture gestures
          child: Stack(
            children: [
              // Field Design / Grass
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3), width: 2),
                  ),
                ),
              ),

              // HUD
              Positioned(
                top: 20,
                left: 40,
                right: 40,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _hudItem("STROKES", "$strokes"),
                    _hudItem("TIME", "${timeLeft}s", color: timeLeft < 10 ? AppColors.error : AppColors.secondary),
                  ],
                ),
              ),

              // Obstacles
              ...obstacles.map((rect) => Positioned(
                left: rect.left,
                top: rect.top,
                child: Container(
                  width: rect.width,
                  height: rect.height,
                  decoration: BoxDecoration(
                    color: Colors.brown.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.brown, width: 2),
                  ),
                ),
              )),

              // Hole
              Positioned(
                left: holePos.dx - holeRadius,
                top: holePos.dy - holeRadius,
                child: Container(
                  width: holeRadius * 2,
                  height: holeRadius * 2,
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                  ),
                ),
              ),

              // Aiming Line
              if (dragStart != null && dragCurrent != null)
                CustomPaint(
                  painter: AimPainter(dragStart!, dragCurrent!),
                ),

              // Ball
              Positioned(
                left: ballPos.dx - ballRadius,
                top: ballPos.dy - ballRadius,
                child: Container(
                  width: ballRadius * 2,
                  height: ballRadius * 2,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(2, 2))],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hudItem(String label, String value, {Color color = AppColors.primaryLight}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textBody)),
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
      ],
    );
  }
}

class AimPainter extends CustomPainter {
  final Offset start;
  final Offset current;

  AimPainter(this.start, this.current);

  @override
  void paint(Canvas canvas, Size size) {
    final dragVector = start - current;
    if (dragVector.distance <= 0.1) return; // Fix blackout/crash on zero distance

    final paint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final cappedDistance = dragVector.distance.clamp(0.0, 150.0);
    final direction = dragVector / dragVector.distance;
    
    canvas.drawLine(start, start + direction * cappedDistance, paint);
    
    final circlePaint = Paint()..color = Colors.white.withValues(alpha: 0.2);
    canvas.drawCircle(start, cappedDistance, circlePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class MiniGolfGameOverScreen extends StatelessWidget {
  const MiniGolfGameOverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: "Game Over",
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_off_rounded, size: 80, color: AppColors.error),
                const SizedBox(height: 24),
                const Text("Time Up!", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.error)),
                const SizedBox(height: 12),
                const Text("You ran out of time. Try again!", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textBody)),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MiniGolfGamePage())),
                    child: const Text("Try Again"),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Exit", style: TextStyle(color: AppColors.textBody)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MiniGolfScoreScreen extends StatelessWidget {
  final int score;
  final int strokes;
  final int timeLeft;

  const MiniGolfScoreScreen({required this.score, required this.strokes, required this.timeLeft, super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: "Goal!",
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stars_rounded, size: 80, color: Colors.amber),
                const SizedBox(height: 24),
                const Text("Nice Shot!", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.amber)),
                const SizedBox(height: 12),
                const Text("Practice Completed", style: TextStyle(color: AppColors.textBody)),
                const SizedBox(height: 32),
                _scoreRow("Strokes", "$strokes"),
                _scoreRow("Time Bonus", "+$timeLeft"),
                const Divider(color: Colors.white10, height: 40),
                Text("TOTAL SCORE", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textBody)),
                Text("$score", style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: AppColors.secondary)),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MiniGolfGamePage())),
                    child: const Text("Play Again"),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Back to Home", style: TextStyle(color: AppColors.textBody)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scoreRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textBody, fontSize: 18)),
          Text(value, style: const TextStyle(color: AppColors.textHeading, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
