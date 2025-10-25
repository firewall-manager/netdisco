package App::Netdisco::Web::Auth::Provider::DBIC;

# DBIC认证提供者模块
# 提供基于数据库的认证功能，支持多种认证方式

use strict;
use warnings;

use base 'Dancer::Plugin::Auth::Extensible::Provider::Base';

# 感谢yanick的补丁
# https://github.com/bigpresh/Dancer-Plugin-Auth-Extensible/pull/24

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Passphrase;
use Digest::MD5;
use Net::LDAP;
use Authen::Radius;
use Authen::TacacsPlus;
use Path::Class;
use File::ShareDir 'dist_dir';
use Try::Tiny;

# 用户认证函数
# 验证用户名和密码
sub authenticate_user {
    my ($self, $username, $password) = @_;
    return unless defined $username;

    # 获取用户详情
    my $user = $self->get_user_details($username) or return;
    return unless $user->in_storage;
    # 匹配密码
    return $self->match_password($password, $user);
}

# 获取用户详情函数
# 从数据库获取用户信息，支持伪用户创建
sub get_user_details {
    my ($self, $username) = @_;

    my $settings = $self->realm_settings;
    my $database = schema($settings->{schema_name})
        or die "No database connection";

    my $users_table     = $settings->{users_resultset}       || 'User';
    my $username_column = $settings->{users_username_column} || 'username';

    # 查找用户记录
    my $user = try {
      $database->resultset($users_table)->find({
          # FIXME: 使用ILIKE进行不区分大小写的用户名匹配，无通配符
          $username_column => { -ilike => quotemeta($username) },
      });
    };

    # 这些设置允许数据库中没有用户
    # 所以创建伪用户条目
    if (not $user and
        (setting('no_auth') or
          (not setting('validate_remote_user')
           and (setting('trust_remote_user') or setting('trust_x_remote_user')) ))) {

        $user = $database->resultset($users_table)
          ->new_result({username => $username});
    }

    return $user;
}

# API令牌验证函数
# 验证API令牌的有效性
sub validate_api_token {
    my ($self, $token) = @_;
    return unless defined $token;

    my $settings = $self->realm_settings;
    my $database = schema($settings->{schema_name})
        or die "No database connection";

    my $users_table  = $settings->{users_resultset}    || 'User';
    my $token_column = $settings->{users_token_column} || 'token';

    # 移除API密钥前缀（应该存在但swagger-ui不添加）
    $token =~ s/^Apikey //i;
    my $user = try {
      $database->resultset($users_table)->find({ $token_column => $token });
    };

    # 检查令牌是否有效且未过期
    return $user
      if $user and $user->in_storage and $user->token_from
        and $user->token_from > (time - setting('api_token_lifetime'));
    return undef;
}

# 获取用户角色函数
# 获取用户的角色列表
sub get_user_roles {
    my ($self, $username) = @_;
    return unless defined $username;

    my $settings = $self->realm_settings;
    my $database = schema($settings->{schema_name})
        or die "No database connection";

    # 首先获取用户详情；既检查用户是否存在，也获取用户ID
    my $user = $self->get_user_details($username)
        or return;

    my $roles       = $settings->{roles_relationship} || 'roles';
    my $role_column = $settings->{role_column}        || 'role';

    # 此方法返回当前用户角色列表
    # 但对于使用trust_remote_user、trust_x_remote_user和no_auth的API
    # 我们需要伪造存在有效的API密钥

    my $api_requires_key =
      (setting('trust_remote_user') or setting('trust_x_remote_user') or setting('no_auth'))
        eq '1' ? 'false' : 'true';

    return [ try {
      $user->$roles->search({}, { bind => [
          $api_requires_key, setting('api_token_lifetime'),
          $api_requires_key, setting('api_token_lifetime'),
        ] })->get_column( $role_column )->all;
    } ];
}

# 密码匹配函数
# 根据用户配置选择相应的认证方式
sub match_password {
    my($self, $password, $user) = @_;
    return unless $user;

    my $settings = $self->realm_settings;
    my $username_column = $settings->{users_username_column} || 'username';

    my $pwmatch_result = 0;
    my $username = $user->$username_column;

    # 根据用户配置选择认证方式
    if ($user->ldap) {
      $pwmatch_result = $self->match_with_ldap($password, $username);
    }
    elsif ($user->radius) {
      $pwmatch_result = $self->match_with_radius($password, $username);
    }
    elsif ($user->tacacs) {
      $pwmatch_result = $self->match_with_tacacs($password, $username);
    }
    else {
      $pwmatch_result = $self->match_with_local_pass($password, $user);
    }

    return $pwmatch_result;
}

# 本地密码匹配函数
# 使用本地存储的密码进行认证
sub match_with_local_pass {
    my($self, $password, $user) = @_;

    my $settings = $self->realm_settings;
    my $password_column = $settings->{users_password_column} || 'password';

    return unless $password and $user->$password_column;

    # 检查密码格式，支持MD5和现代密码哈希
    if ($user->$password_column !~ m/^{[A-Z]+}/) {
        # 使用MD5哈希匹配
        my $sum = Digest::MD5::md5_hex($password);

        if ($sum eq $user->$password_column) {
            if (setting('safe_password_store')) {
                # 如果成功且允许，升级密码
                $user->update({password => passphrase($password)->generate});
            }
            return 1;
        }
        else {
            return 0;
        }
    }
    else {
        # 使用现代密码哈希匹配
        return passphrase($password)->matches($user->$password_column);
    }
}

# LDAP密码匹配函数
# 使用LDAP服务器进行认证
sub match_with_ldap {
    my($self, $pass, $user) = @_;

    return unless setting('ldap') and ref {} eq ref setting('ldap');
    my $conf = setting('ldap');

    my $ldapuser = $conf->{user_string};
    $ldapuser =~ s/\%USER\%?/$user/egi;

    # 如果我们可以作为匿名或代理用户绑定
    # 搜索用户的专有名称
    if ($conf->{proxy_user}) {
        my $user   = $conf->{proxy_user};
        my $pass   = $conf->{proxy_pass};
        my $attrs  = ['distinguishedName'];
        my $result = _ldap_search($ldapuser, $attrs, $user, $pass);
        $ldapuser  = $result->[0] if ($result->[0]);
    }
    # 否则，如果我们不能搜索且不使用AD，则通过追加base构造DN
    elsif ($ldapuser =~ m/=/) {
        $ldapuser = "$ldapuser,$conf->{base}";
    }

    # 尝试连接每个LDAP服务器
    foreach my $server (@{$conf->{servers}}) {
        my $opts = $conf->{opts} || {};
        my $ldap = Net::LDAP->new($server, %$opts) or next;
        my $msg  = undef;

        # 启动TLS连接
        if ($conf->{tls_opts} ) {
            $msg = $ldap->start_tls(%{$conf->{tls_opts}});
        }

        # 尝试绑定用户
        $msg = $ldap->bind($ldapuser, password => $pass);
        $ldap->unbind(); # 关闭会话

        return 1 unless $msg->code();
    }

    return undef;
}

# LDAP搜索函数
# 在LDAP服务器中搜索用户信息
sub _ldap_search {
    my ($filter, $attrs, $user, $pass) = @_;
    my $conf = setting('ldap');

    return undef unless defined($filter);
    return undef if (defined $attrs and ref [] ne ref $attrs);

    # 尝试连接每个LDAP服务器
    foreach my $server (@{$conf->{servers}}) {
        my $opts = $conf->{opts} || {};
        my $ldap = Net::LDAP->new($server, %$opts) or next;
        my $msg  = undef;

        # 启动TLS连接
        if ($conf->{tls_opts}) {
            $msg = $ldap->start_tls(%{$conf->{tls_opts}});
        }

        # 绑定用户或匿名绑定
        if ( $user and $user ne 'anonymous' ) {
            $msg = $ldap->bind($user, password => $pass);
        }
        else {
            $msg = $ldap->bind();
        }

        # 执行搜索
        $msg = $ldap->search(
          base   => $conf->{base},
          filter => "($filter)",
          attrs  => $attrs,
        );

        $ldap->unbind(); # 关闭会话

        my $entries = [$msg->entries];
        return $entries unless $msg->code();
    }

    return undef;
}

# RADIUS密码匹配函数
# 使用RADIUS服务器进行认证
sub match_with_radius {
  my($self, $pass, $user) = @_;
  return unless setting('radius') and ref {} eq ref setting('radius');

  my $conf = setting('radius');
  my $servers = (ref [] eq ref $conf->{'server'}
    ? $conf->{'server'} : [$conf->{'server'}]);
  # 创建RADIUS客户端
  my $radius = Authen::Radius->new(
    NodeList => $servers,
    Secret   => $conf->{'secret'},
    TimeOut  => $conf->{'timeout'} || 15,
  );
  # 加载RADIUS字典
  my $dict_dir = Path::Class::Dir->new( dist_dir('App-Netdisco') )
    ->subdir('contrib')->subdir('raddb')->file('dictionary')->stringify;
  Authen::Radius->load_dictionary($dict_dir);

  # 添加用户属性
  $radius->add_attributes(
     { Name => 'User-Name',         Value => $user },
     { Name => 'User-Password',     Value => $pass }
  );

  # 添加供应商特定属性
  if ($conf->{'vsa'}) {
    foreach my $vsa (@{$conf->{'vsa'}}) {
      $radius->add_attributes(
        {
          Name   => $vsa->{'name'},
          Value  => $vsa->{'value'},
          Type   => $vsa->{'type'},
          Vendor => $vsa->{'vendor'},
          Tag    => $vsa->{'tag'}
        },
      );
    }
  }

  # 发送访问请求
  $radius->send_packet(ACCESS_REQUEST);

  # 接收响应
  my $type = $radius->recv_packet();
  my $radius_return = ($type eq ACCESS_ACCEPT) ? 1 : 0;

  return $radius_return;
}

# TACACS+密码匹配函数
# 使用TACACS+服务器进行认证
sub match_with_tacacs {
  my($self, $pass, $user) = @_;
  return unless setting('tacacs') and ref [] eq ref setting('tacacs');

  my $conf = setting('tacacs');
  # 创建TACACS+客户端
  my $tacacs = new Authen::TacacsPlus(@$conf);
  if (not $tacacs) {
      debug sprintf('auth error: Authen::TacacsPlus: %s', Authen::TacacsPlus::errmsg());
      return undef;
  }

  # 执行认证
  my $tacacs_return = $tacacs->authen($user,$pass);
  if (not $tacacs_return) {
      debug sprintf('error: Authen::TacacsPlus: %s', Authen::TacacsPlus::errmsg());
  }
  $tacacs->close();

  return $tacacs_return;
}

1;
