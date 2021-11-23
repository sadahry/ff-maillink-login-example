import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_signin_button/button_builder.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final ActionCodeSettings _setting = ActionCodeSettings(
  androidPackageName: 'com.example.ff_maillink_login_example',
  // アプリのリリースバージョン指定。どんなバージョンでもアプリにリンクするよう'0'を指定
  androidMinimumVersion: '0',
  androidInstallApp: true,
  handleCodeInApp: true,
  iOSBundleId: 'com.example.ffMaillinkLoginExample',
  url: 'https://ffloginexample.page.link/emailLink',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

/// コード簡略化のためクラス化
class ScaffoldSnackBar {
  ScaffoldSnackBar(this._context);
  final BuildContext _context;

  factory ScaffoldSnackBar.of(BuildContext context) {
    return ScaffoldSnackBar(context);
  }

  void show(String message) {
    ScaffoldMessenger.of(_context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }
}

/// 永続層（SharedPreferences）にメールアドレスを保持
class EmailStore {
  EmailStore(this._prefs);
  final SharedPreferences _prefs;

  Future<String?> get() async {
    return _prefs.getString("email");
  }

  Future<void> set(String email) async {
    await _prefs.setString("email", email);
  }

  Future<void> clear() async {
    await _prefs.remove("email");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData.dark(),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  late final EmailStore _emailStore;

  User? user;
  String? email;

  @override
  void initState() {
    _initAsync();
    super.initState();
  }

  Future<void> _initAsync() async {
    await _initAuth();
    await _initEmail();
    await _initDynamicLink();
  }

  Future<void> _initAuth() async {
    _auth.userChanges().listen(
          (event) => setState(() => user = event),
        );
  }

  Future<void> _initEmail() async {
    _emailStore = EmailStore(await SharedPreferences.getInstance());

    // メールリンクの送信後、アプリで入力したメールアドレスをEmailStoreに保持している
    // このメールアドレスを利用して、メールリンクに含まれるものとアプリで入力したものが一致することを確認
    _emailStore.get().then(
          (value) => setState(() => email = value),
        );
  }

  Future<void> _initDynamicLink() async {
    // リンクからアプリへ遷移するとき、アプリが開いていると発動
    FirebaseDynamicLinks.instance.onLink(
        onSuccess: _verifyDynamicLink,
        onError: (OnLinkErrorException e) async {
          ScaffoldSnackBar.of(context)
              .show('Error signing in with email link $e');
        });

    // リンクからアプリへ遷移するとき、アプリが開いていないと発動
    FirebaseDynamicLinks.instance.getInitialLink().then(
          _verifyDynamicLink,
        );
  }

  /// メールリンクの検証にのみ利用
  Future<dynamic> _verifyDynamicLink(PendingDynamicLinkData? _data) async {
    // すでにSigninしている場合はスキップ
    if (user != null) return;
    // メールアドレスの入力がない場合はスキップ
    if (email == null) return;

    final String? _deepLink = _data?.link.toString();
    if (_deepLink == null) return;

    // リンク（＝URL）が、メールリンクかどうか検証
    if (_auth.isSignInWithEmailLink(_deepLink)) {
      // メールリンクに含まれる認証情報でサインイン
      // 成功したらFirebase Authenticationにユーザーを作成（すでに存在する場合はログインのみ）
      _auth.signInWithEmailLink(email: email!, emailLink: _deepLink).then(
        (value) {
          ScaffoldSnackBar.of(context)
              .show('Successfully signed in! by: ${value.user!.email!}');
        },
      ).catchError(
        (onError) {
          ScaffoldSnackBar.of(context)
              .show('Error signing in with email link $onError');
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Form(
        key: _formKey,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: email == null
                  ?
                  // メールリンクの送信がされていないとき
                  <Widget>[
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (String? value) {
                          if (value!.isEmpty) {
                            return 'Please enter some text';
                          }
                          return null;
                        },
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        child: SignInButtonBuilder(
                          icon: Icons.person_add,
                          backgroundColor: Colors.blueGrey,
                          text: 'Register',
                          onPressed: () {
                            if (_formKey.currentState!.validate()) {
                              _register();
                            }
                          },
                        ),
                      ),
                    ]
                  : user == null
                      ?
                      // メールリンクの送信後、リンクの検証がされていないとき
                      <Widget>[
                          Container(
                            alignment: Alignment.center,
                            child: const Text('Verify email link.'),
                          ),
                          TextButton(
                            child: const Text('Retry'),
                            onPressed: () => _retry(),
                          ),
                        ]
                      :
                      // メールリンクが検証されて、サインインが完了したとき
                      <Widget>[
                          Container(
                            alignment: Alignment.center,
                            child: Text("Logged in: $email"),
                          ),
                          TextButton(
                            child: const Text('Sign out'),
                            onPressed: () => _signOut(),
                          ),
                        ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _register() async {
    final String _email = _emailController.text;
    _auth
        .sendSignInLinkToEmail(
      email: _email,
      actionCodeSettings: _setting,
    )
        .then(
      (_) async {
        // メールリンクの送信に成功したあと、メールアドレスをEmailStoreに保存
        _emailStore.set(_email).then(
              (_) => setState(() => email = _email),
            );
        ScaffoldSnackBar.of(context)
            .show("Successfully send sign in email link!");
      },
    ).catchError(
      (onError) {
        ScaffoldSnackBar.of(context)
            .show('Error send sign in email link $onError');
      },
    );
  }

  Future<void> _retry() async {
    // メールアドレスの保存を取消し、再度フォーム画面を表示
    _emailStore.clear().then(
          (_) => setState(() => email = null),
        );
  }

  Future<void> _signOut() async {
    _auth.signOut().then(
      (_) async {
        // uidはユーザーが識別できない文字列(e.g 7yL3RIe44VaVFS6Ar625fkXvtfn2)であるため、emailを利用
        // final String _id = user!.uid;
        final String _id = email!;
        // 同時にメールアドレスもEmailStoreから削除
        await _emailStore.clear().then(
              (_) => setState(() => email = null),
            );
        ScaffoldSnackBar.of(context).show('$_id has successfully signed out.');
      },
    ).catchError(
      (onError) {
        ScaffoldSnackBar.of(context).show('Error sign out $onError');
      },
    );
  }
}
