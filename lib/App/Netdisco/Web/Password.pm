package App::Netdisco::Web::Password;

# 密码管理Web模块
# 提供用户密码修改功能

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Passphrase;

use Digest::MD5 ();

# 生成密码哈希函数
# 根据配置选择安全的密码存储或MD5哈希
sub _make_password {
  my $pass = (shift || passphrase->generate_random);
  if (setting('safe_password_store')) {
    return passphrase($pass)->generate;
  }
  else {
    return Digest::MD5::md5_hex($pass),;
  }
}

# 密码修改失败处理函数
# 设置失败标志并返回密码模板
sub _bail {
  var('passchange_failed' => 1);
  return template 'password.tt', {}, {layout => 'main'};
}

# 密码修改路由
# 处理用户密码修改请求
any ['get', 'post'] => '/password' => require_login sub {
  my $old     = param('old');
  my $new     = param('new');
  my $confirm = param('confirm');

  if (request->is_post) {

    # 验证输入参数
    unless ($old and $new and $confirm and ($new eq $confirm)) {
      return _bail();
    }

    # 验证旧密码
    my ($success, $realm) = authenticate_user(session('logged_in_user'), $old);
    return _bail() if not $success;

    # 获取用户记录
    my $user = schema('netdisco')->resultset('User')->find({username => session('logged_in_user')});
    return _bail() if not $user;

    # 更新密码
    $user->update({password => _make_password($new)});
    var('passchange_ok' => 1);
  }

  template 'password.tt', {}, {layout => 'main'};
};

true;
