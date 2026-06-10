import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'providers/toy_state.dart';
import 'providers/navigation_state.dart';
import 'providers/playbook_state.dart';
import 'services/hermes_api.dart';
import 'services/deepseek_api.dart';
import 'providers/api_config.dart';
import 'services/ble/toy_registry.dart';
import 'pages/profile_page.dart';
import 'pages/bluetooth_page.dart';
import 'pages/chat_page.dart';
import 'pages/play_tab.dart';

/// 底部导航栏主页面
///
/// 四 Tab: 个人 | 蓝牙 | 设计 | 玩法
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 2;

  late final List<Widget> _tabs = [
    const ProfilePage(),
    BluetoothPage(registry: context.read<ToyRegistry>()),
    const ChatPage(),
    const PlayTab(),
  ];

  @override
  void initState() {
    super.initState();
    // 监听 NavigationState 的 tab 切换
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NavigationState>().addListener(_onNavChange);
    });
  }

  void _onNavChange() {
    final navState = context.read<NavigationState>();
    if (navState.tabIndex != _currentIndex) {
      setState(() => _currentIndex = navState.tabIndex);
    }
  }

  @override
  void dispose() {
    // 安全移除 listener
    try {
      context.read<NavigationState>().removeListener(_onNavChange);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppTheme.bgSurface, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppTheme.bgCard,
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: AppTheme.textMuted,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          onTap: (index) {
            setState(() => _currentIndex = index);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: '个人',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bluetooth_outlined),
              activeIcon: Icon(Icons.bluetooth_connected),
              label: '蓝牙',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: '设计',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.play_circle_outline),
              activeIcon: Icon(Icons.play_circle_filled),
              label: '玩法',
            ),
          ],
        ),
      ),
    );
  }
}

/// 应用入口
class YokonexPlayApp extends StatelessWidget {
  const YokonexPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ToyState()),
        ChangeNotifierProvider(create: (_) => ToyRegistry()),
        ChangeNotifierProvider(create: (_) => NavigationState()),
        ChangeNotifierProvider(create: (_) {
          final ps = PlaybookState();
          ps.loadFromStorage(); // 启动时从本地存储加载
          return ps;
        }),
        ChangeNotifierProvider(create: (_) {
          final cfg = ApiConfig();
          cfg.init().then((_) => cfg.importFromHermes());
          return cfg;
        }),
        ChangeNotifierProvider(create: (_) => HermesApiService()),
        ChangeNotifierProvider(create: (_) => DeepseekApiService()),
      ],
      child: MaterialApp(
        title: 'YOKONEX Play',
        theme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        home: const MainScreen(),
      ),
    );
  }
}
