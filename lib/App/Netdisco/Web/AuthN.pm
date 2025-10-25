package App::Netdisco::Web::AuthN;

# 认证Web模块
# 提供用户认证和会话管理功能

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Swagger;

use App::Netdisco;    # 安全的无操作，但独立测试需要
use App::Netdisco::Util::Web 'request_is_api';
use MIME::Base64;
use URI::Based;

# 确保无论用户被重定向到哪里，我们都有一个链接
# 回到他们请求的页面
hook 'before' => sub {
  params->{return_url} ||= ((request->path ne uri_for('/')->path) ? request->uri : uri_for(setting('web_home'))->path);
};

# 尝试根据头部或配置设置找到有效的用户名
sub _get_delegated_authn_user {
  my $username = undef;

  # 检查X-REMOTE_USER头部
  if (  setting('trust_x_remote_user')
    and scalar request->header('X-REMOTE_USER')
    and length scalar request->header('X-REMOTE_USER')) {

    ($username = scalar request->header('X-REMOTE_USER')) =~ s/@[^@]*$//;
  }

  # 检查REMOTE_USER环境变量
  elsif (setting('trust_remote_user') and defined $ENV{REMOTE_USER} and length $ENV{REMOTE_USER}) {

    ($username = $ENV{REMOTE_USER}) =~ s/@[^@]*$//;
  }

  # 这也适用于API调用
  elsif (setting('no_auth')) {
    $username = 'guest';
  }

  return unless $username;

  # 来自Dancer::Plugin::Auth::Extensible的内部
  my $provider = Dancer::Plugin::Auth::Extensible::auth_provider('users');

  # 如果validate_remote_user=false，可能会合成用户
  return $provider->get_user_details($username);
}

# Dancer在看到自己的cookie时会创建会话。对于API和各种自动登录选项，
# 我们需要引导会话。如果没有传递认证数据，钩子简单返回，不设置会话，
# 用户被重定向到登录页面
hook 'before' => sub {

  # 如果请求是不需要会话的端点则返回
  return
    if (request->path eq uri_for('/login')->path
    or request->path eq uri_for('/logout')->path
    or request->path eq uri_for('/swagger.json')->path
    or index(request->path, uri_for('/swagger-ui')->path) == 0);

  # Dancer会向客户端发出cookie，这可能会被返回并
  # 导致API调用在没有传递令牌的情况下成功。销毁会话
  session->destroy if request_is_api;

  # ...否则，如果Dancer读取其cookie正常，我们可以短路
  return if session('logged_in_user');

  my $delegated = _get_delegated_authn_user();

  # 这个顺序允许在给定凭据时覆盖委托认证

  # 防止委托认证配置但没有有效用户
  if ((not $delegated) and (setting('trust_x_remote_user') or setting('trust_remote_user'))) {
    session->destroy;
    request->path_info('/');
  }

  # API调用必须严格符合路径和头部要求
  elsif (request_is_api and request->header('Authorization')) {

    # 来自Dancer::Plugin::Auth::Extensible的内部
    my $provider = Dancer::Plugin::Auth::Extensible::auth_provider('users');

    my $token = request->header('Authorization');
    my $user  = $provider->validate_api_token($token) or return;

    session(logged_in_user       => $user->username);
    session(logged_in_user_realm => 'users');
  }
  elsif ($delegated) {
    session(logged_in_user       => $delegated->username);
    session(logged_in_user_realm => 'users');
  }
  else {
    # 用户没有认证 - 强制到'/'的处理器
    request->path_info('/');
  }
};

# 覆盖默认的login_handler，以便我们可以在数据库中记录访问
swagger_path {
  description => 'Obtain an API Key',
  tags        => ['General'],
  path        => (setting('url_base') ? setting('url_base')->with('/login')->path : '/login'),
  parameters  => [],
  responses   => {default => {examples => {'application/json' => {api_key => 'cc9d5c02d8898e5728b7d7a0339c0785'}}},},
  },
  post '/login' => sub {
  my $api = ((request->accept and request->accept =~ m/(?:json|javascript)/) ? true : false);

  # 来自Dancer::Plugin::Auth::Extensible的内部
  my $provider = Dancer::Plugin::Auth::Extensible::auth_provider('users');

  # 从API使用的BasicAuth头部获取认证数据，放入params
  my $authheader = request->header('Authorization');
  if (defined $authheader and $authheader =~ /^Basic (.*)$/i) {
    my ($u, $p) = split(m/:/, (MIME::Base64::decode($1) || ":"));
    params->{username} = $u;
    params->{password} = $p;
  }

  # 验证认证
  my ($success, $realm) = authenticate_user(param('username'), param('password'));

  # 或尝试从其他地方获取用户
  my $delegated = _get_delegated_authn_user();

  if (
    (
      $success
      and not

      # 防止委托认证配置但没有有效用户（然后必须忽略params）
      (not $delegated and (setting('trust_x_remote_user') or setting('trust_remote_user')))
    )
    or $delegated
  ) {

    # 这个顺序允许在给定凭据时覆盖委托用户
    my $user = ($success ? $provider->get_user_details(param('username')) : $delegated);

    session logged_in_user       => $user->username;
    session logged_in_fullname   => ($user->fullname || '');
    session logged_in_user_realm => ($realm          || 'users');

    # 记录用户日志
    schema('netdisco')->resultset('UserLog')->create({
      username => session('logged_in_user'),
      userip   => request->remote_address,
      event    => (sprintf 'Login (%s)', ($api ? 'API' : 'WebUI')),
      details  => param('return_url'),
    });
    $user->update({last_on => \'LOCALTIMESTAMP'});

    if ($api) {
      header('Content-Type' => 'application/json');

      # 如果有当前有效令牌，则重新发出并重置计时器
      $user->update({
        token_from => time, ($provider->validate_api_token($user->token) ? () : (token => \'md5(random()::text)')),
      })->discard_changes();
      return to_json {api_key => $user->token};
    }

    redirect((scalar URI::Based->new(param('return_url'))->path_query) || '/');
  }
  else {
    # 使会话cookie无效
    session->destroy;

    # 记录登录失败日志
    schema('netdisco')->resultset('UserLog')->create({
      username => param('username'),
      userip   => request->remote_address,
      event    => (sprintf 'Login Failure (%s)', ($api ? 'API' : 'WebUI')),
      details  => param('return_url'),
    });

    if ($api) {
      header('Content-Type' => 'application/json');
      status('unauthorized');
      return to_json {error => 'authentication failed'};
    }

    vars->{login_failed}++;
    forward uri_for('/login'), {login_failed => 1, return_url => param('return_url')}, {method => 'GET'};
  }
  };

# 呃，*呕吐*，但D::P::Swagger无法通过swagger_path设置这个
# 必须在上面声明路径之后
Dancer::Plugin::Swagger->instance->doc->{paths}
  ->{(setting('url_base') ? setting('url_base')->with('/login')->path : '/login')}->{post}->{security}->[0]->{BasicAuth}
  = [];

# 我们覆盖了默认的login_handler，所以logout也必须处理
swagger_path {
  description => 'Destroy user API Key and session cookie',
  tags        => ['General'],
  path        => (setting('url_base') ? setting('url_base')->with('/logout')->path : '/logout'),
  parameters  => [],
  responses   => {default => {examples => {'application/json' => {}}}},
  },
  get '/logout' => sub {
  my $api = ((request->accept and request->accept =~ m/(?:json|javascript)/) ? true : false);

  # 清除API令牌
  my $user = schema('netdisco')->resultset('User')->find({username => session('logged_in_user')});
  $user->update({token => undef, token_from => undef})->discard_changes() if $user and $user->in_storage;

  # 使会话cookie无效
  session->destroy;

  # 记录登出日志
  schema('netdisco')->resultset('UserLog')->create({
    username => session('logged_in_user'),
    userip   => request->remote_address,
    event    => (sprintf 'Logout (%s)', ($api ? 'API' : 'WebUI')),
    details  => '',
  });

  if ($api) {
    header('Content-Type' => 'application/json');
    return to_json {};
  }

  redirect uri_for(setting('web_home'))->path;
  };

# 当require_role不成功时用户被重定向到这里
any qr{^/(?:login(?:/denied)?)?} => sub {
  my $api = ((request->accept and request->accept =~ m/(?:json|javascript)/) ? true : false);

  if ($api) {
    header('Content-Type' => 'application/json');
    status('unauthorized');
    return to_json {error => 'not authorized', return_url => param('return_url'),};
  }
  elsif (defined request->header('X-Requested-With') and request->header('X-Requested-With') eq 'XMLHttpRequest') {
    status('unauthorized');
    return '<div class="span2 alert alert-error"><i class="icon-ban-circle"></i> Error: unauthorized.</div>';
  }
  else {
    template 'index', {return_url => param('return_url')}, {layout => 'main'};
  }
};

true;
