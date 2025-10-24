package App::Netdisco::Web;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;

use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Swagger;

use Dancer::Error;
use Dancer::Continuation::Route::ErrorSent;

use URI ();
use Socket6 (); # to ensure dependency is met
use HTML::Entities (); # to ensure dependency is met
use URI::QueryParam (); # part of URI, to add helper methods
use MIME::Base64 'encode_base64';
use Path::Class 'dir';
use Module::Load ();
use Data::Visitor::Tiny;
use Scalar::Util 'blessed';
use Storable 'dclone';
use URI::Based;

use App::Netdisco::Util::Web qw/
  interval_to_daterange
  request_is_api
  request_is_api_report
  request_is_api_search
/;
use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;

BEGIN {
  no warnings 'redefine';

  # 修复Dancer重定向问题
  # https://github.com/PerlDancer/Dancer/issues/967
  *Dancer::_redirect = sub {
      my ($destination, $status) = @_;
      my $response = Dancer::SharedData->response;
      $response->status($status || 302);
      $response->headers('Location' => $destination);
  };

  # 比使用Dancer::Plugin::Res处理JSON更简洁
  *Dancer::send_error = sub {
      my ($body, $status) = @_;
      if (request_is_api) {
        status $status || 400;
        $body = '' unless defined $body;
        Dancer::Continuation::Route::ErrorSent->new(
            return_value => to_json { error => $body, return_url => param('return_url') }
        )->throw;
      }
      Dancer::Continuation::Route::ErrorSent->new(
          return_value => Dancer::Error->new(
              message => $body,
              code => $status || 500)->render()
      )->throw;
  };

  # 如果设置了租户，插入/t/$tenant
  # 这对于构建链接很好，但对于与request->path比较不好
  # 因为当is_forward()时request->path会改变...
  *Dancer::Request::uri_for = sub {
    my ($self, $part, $params, $dont_escape) = @_;
    my $uri = $self->base;

    if (vars->{'tenant'}) {
        $part = '/t/'. vars->{'tenant'} . $part;
    }

    # 确保base和新部分之间只有一个斜杠
    my $base = $uri->path;
    $base =~ s|/$||;
    $part =~ s|^/||;
    $uri->path("$base/$part");

    $uri->query_form($params) if $params;

    return $dont_escape ? uri_unescape($uri->canonical) : $uri->canonical;
  };

  # ...所以这里我们也对request->path进行猴子补丁
  *Dancer::Request::path = sub {
    die "path是访问器不是修改器" if scalar @_ > 1;
    my $self = shift;
    $self->_build_path() unless $self->{path};

    if (vars->{'tenant'} and $self->{path} !~ m{/t/}) {
        my $path = $self->{path};
        my $base = setting('path');
        my $tenant = '/t/' . vars->{'tenant'};

        $tenant = ($base . $tenant) if $base ne '/';
        $tenant .= '/' if $base eq '/';
        $path =~ s/^$base/$tenant/;

        return $path;
    }
    return $self->{path};
  };

  # 实现same_site支持
  # 来自 https://github.com/PerlDancer/Dancer-Session-Cookie/issues/20
  *Dancer::Session::Cookie::_cookie_params = sub {
      my $self     = shift;
      my $name     = $self->session_name;
      my $duration = $self->_session_expires_as_duration;
      my %cookie   = (
          name      => $name,
          value     => $self->_cookie_value,
          path      => setting('session_cookie_path') || '/',
          domain    => setting('session_domain'),
          secure    => setting('session_secure'),
          http_only => setting("session_is_http_only") // 1,
          same_site => setting("session_same_site"),
      );
      if ( defined $duration ) {
          $cookie{expires} = time + $duration;
      }
      return %cookie;
  };
}

use App::Netdisco::Web::AuthN;
use App::Netdisco::Web::Static;
use App::Netdisco::Web::Search;
use App::Netdisco::Web::Device;
use App::Netdisco::Web::Report;
use App::Netdisco::Web::API::Objects;
use App::Netdisco::Web::API::Queue;
use App::Netdisco::Web::AdminTask;
use App::Netdisco::Web::TypeAhead;
use App::Netdisco::Web::PortControl;
use App::Netdisco::Web::Statistics;
use App::Netdisco::Web::Password;
use App::Netdisco::Web::CustomFields;
use App::Netdisco::Web::GenericReport;

# 加载Web插件
# 该方法用于动态加载Web插件模块
sub _load_web_plugins {
  my $plugin_list = shift;

  foreach my $plugin (@$plugin_list) {
      # 处理X::前缀的插件（扩展插件）
      $plugin =~ s/^X::/+App::NetdiscoX::Web::Plugin::/;
      # 添加默认插件命名空间
      $plugin = 'App::Netdisco::Web::Plugin::'. $plugin
        if $plugin !~ m/^\+/;
      # 移除+前缀
      $plugin =~ s/^\+//;

      $ENV{ND2_LOG_PLUGINS} && debug "正在加载Web插件 $plugin";
      Module::Load::load $plugin;
  }
}

# 加载配置的Web插件
if (setting('web_plugins') and ref [] eq ref setting('web_plugins')) {
    _load_web_plugins( setting('web_plugins') );
}

# 加载额外的Web插件（从站点插件目录）
if (setting('extra_web_plugins') and ref [] eq ref setting('extra_web_plugins')) {
    unshift @INC, dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'site_plugins')->stringify;
    _load_web_plugins( setting('extra_web_plugins') );
}

# 为每个管理任务创建路由
foreach my $tag (keys %{ setting('_admin_tasks') }) {
    my $code = sub {
        # 让ajax像标签页一样工作
        params->{tab} = $tag;

        var(nav => 'admin');
        template 'admintask', {
          task => setting('_admin_tasks')->{ $tag },
        }, { layout => 'main' };
    };

    # 根据任务的角色要求设置路由权限
    if (setting('_admin_tasks')->{ $tag }->{ 'roles' }) {
        get "/admin/$tag" => require_any_role setting('_admin_tasks')->{ $tag }->{ 'roles' } => $code;
    }
    else {
        get "/admin/$tag" => require_role admin => $code;
    }
}


# 插件加载后，添加我们自己的模板路径
push @{ config->{engines}->{netdisco_template_toolkit}->{INCLUDE_PATH} },
     setting('views');

# 按标签对已加载的报告进行排序
foreach my $cat (@{ setting('_report_order') }) {
    setting('_reports_menu')->{ $cat } ||= [];
    setting('_reports_menu')->{ $cat }
      = [ sort { setting('_reports')->{$a}->{'label'}
                 cmp
                 setting('_reports')->{$b}->{'label'} }
          @{ setting('_reports_menu')->{ $cat } } ];
}

# deployment.yml中的任何模板路径（应该覆盖插件）
if (setting('template_paths') and ref [] eq ref setting('template_paths')) {
    if (setting('site_local_files')) {
      push @{setting('template_paths')},
         dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'nd-site-local', 'share')->stringify,
         dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'nd-site-local', 'share', 'views')->stringify;
    }
    unshift @{ config->{engines}->{netdisco_template_toolkit}->{INCLUDE_PATH} },
      @{setting('template_paths')};
}

# 从数据库加载cookie密钥
setting('session_cookie_key' => undef);
setting('session_cookie_key' => 'this_is_for_testing_only')
  if $ENV{HARNESS_ACTIVE};
eval {
  my $sessions = schema('netdisco')->resultset('Session');
  my $skey = $sessions->find({id => 'dancer_session_cookie_key'});
  setting('session_cookie_key' => $skey->get_column('a_session')) if $skey;
};
Dancer::Session::Cookie::init(session);

# 修复 https://github.com/PerlDancer/Dancer/issues/935 的变通方法
hook after_error_render => sub { setting('layout' => 'main') };

# 构建端口详情列列表
{
  my @port_columns =
    sort { $a->{idx} <=> $b->{idx} }
    map  {{ name => $_, %{ setting('sidebar_defaults')->{'device_ports'}->{$_} } }}
    grep { $_ =~ m/^c_/ } keys %{ setting('sidebar_defaults')->{'device_ports'} };

  # 在指定位置插入额外的端口列
  splice @port_columns, setting('device_port_col_idx_right') + 1, 0,
    grep {$_->{position} eq 'right'} @{ setting('_extra_device_port_cols') };
  splice @port_columns, setting('device_port_col_idx_mid') + 1, 0,
    grep {$_->{position} eq 'mid'}   @{ setting('_extra_device_port_cols') };
  splice @port_columns, setting('device_port_col_idx_left') + 1, 0,
    grep {$_->{position} eq 'left'}  @{ setting('_extra_device_port_cols') };

  set('port_columns' => \@port_columns);

  # 更新sidebar_defaults，以便扫描参数的钩子看到新的插件列
  setting('sidebar_defaults')->{'device_ports'}->{ $_->{name} } = $_
    for @port_columns;
}

# 构建租户查找表
{
    set('tenant_data' => {
        map { ( $_->{tag} => { displayname => $_->{'displayname'},
                               tag => $_->{'tag'},
                               path => config->{'url_base'}->with("/t/$_->{tag}")->path } ) }
            @{ setting('tenant_databases') },
            { tag => 'netdisco', displayname => (setting('database')->{displayname} || 'Default') }
    });
    config->{'tenant_data'}->{'netdisco'}->{'path'}
      = URI::Based->new((config->{path} eq '/') ? '' : config->{path})->path;
    set('tenant_tags' => [  map { $_->{'tag'} }
                           sort { $a->{'displayname'} cmp $b->{'displayname'} }
                                values %{ config->{'tenant_data'} } ]);
}

hook 'before' => sub {
  my $key = request->path;
  if (param('tab') and ($key !~ m/ajax/)) {
      $key .= ('/' . param('tab'));
  }
  $key =~ s|.*/(\w+)/(\w+)$|${1}_${2}|;
  var(sidebar_key => $key);

  # 修剪空白字符
  params->{'q'} =~ s/^\s+|\s+$//g if param('q');

  # 将侧边栏默认值复制到变量中，以便我们可以对其进行操作
  foreach my $sidebar (keys %{setting('sidebar_defaults')}) {
    vars->{'sidebar_defaults'}->{$sidebar} = { map {
      ($_ => setting('sidebar_defaults')->{$sidebar}->{$_}->{'default'})
    } keys %{setting('sidebar_defaults')->{$sidebar}} };
  }
};

# swagger提交"false"参数，而web UI不这样做 - 删除它们
# 这样测试参数存在性的代码仍然可以正常工作
hook 'before' => sub {
  return unless request_is_api_report or request_is_api_search;
  map {delete params->{$_} if params->{$_} eq 'false'} keys %{params()};
};

hook 'before_template' => sub {
  # 来自导航栏的搜索或报告，或侧边栏重置，可以忽略参数
  return if param('firstsearch')
    or var('sidebar_key') !~ m/^\w+_\w+$/;

  # 更新默认值以包含传递的URL参数
  # （这遵循从config.yml的初始复制，然后是cookie恢复）
  var('sidebar_defaults')->{var('sidebar_key')}->{$_} = param($_)
    for keys %{ var('sidebar_defaults')->{var('sidebar_key')} || {} };
};

hook 'before_template' => sub {
    my $tokens = shift;

    # 快速base64编码
    $tokens->{atob} = sub { encode_base64(shift, '') };

    # 允许可移植的静态内容
    $tokens->{uri_base} = request->base->path
      if request->base->path ne '/';
    $tokens->{uri_base} .= ('/t/'. vars->{'tenant'})
      if vars->{'tenant'};

    # 允许可移植的动态内容
    $tokens->{uri_for} = sub { uri_for(@_)->path_query };

    # 当前查询字符串，用于从ajax模板内重新提交
    my $queryuri = URI->new();
    $queryuri->query_param($_ => param($_))
      for grep {$_ ne 'return_url'} keys %{params()};
    $tokens->{my_query} = $queryuri->query();

    # 根据only/no设置隐藏自定义字段
    $tokens->{permitted_by_acl} = sub {
        my ($thing, $config) = @_;
        return false unless $thing and $config;

        return if acl_matches($thing, ($config->{no} || []));
        return unless acl_matches_only($thing, ($config->{only} || []));
        return true;
    };

    # 访问已登录用户的角色（基于RBAC）
    # 角色将是"admin" "port_control" "radius"或"ldap"
    $tokens->{user_has_role} = sub {
        my ($role, $device) = @_;
        return false unless $role;

        return user_has_role($role) if $role ne 'port_control';
        return false unless user_has_role('port_control');
        return true if not $device;

        my $user = logged_in_user or return false;
        return true unless $user->portctl_role;

        # 这包含合并的yaml和数据库配置
        my $acl = setting('portctl_by_role')->{$user->portctl_role};
        if ($acl and (ref $acl eq q{} or ref $acl eq ref [])) {
            return true if acl_matches($device, $acl);
        }
        elsif ($acl and ref $acl eq ref {}) {
            foreach my $key (grep { defined } keys %$acl) {
                # 左侧匹配设备，右侧匹配端口
                # 但我们不关心端口
                return true if acl_matches($device, $key);
            }
        }

        # 分配了未知角色
        return false;
    };

    # 从模板内创建日期范围
    $tokens->{to_daterange}  = sub { interval_to_daterange(@_) };

    # DataTables每页记录菜单的数据结构
    $tokens->{table_showrecordsmenu} =
      to_json( setting('table_showrecordsmenu') );

    # 链接搜索将使用这些默认URL路径参数
    foreach my $sidebar_key (keys %{ var('sidebar_defaults') }) {
        my ($mode, $report) = ($sidebar_key =~ m/(\w+)_(\w+)/);
        if ($mode =~ m/^(?:search|device)$/) {
            $tokens->{$sidebar_key} = uri_for("/$mode", {tab => $report});
        }
        elsif ($mode =~ m/^report$/) {
            $tokens->{$sidebar_key} = uri_for("/$mode/$report");
        }
        elsif ($mode =~ m/^admintask$/) {
            $tokens->{$sidebar_key} = uri_for("/$mode/$report");
        }

        foreach my $col (keys %{ var('sidebar_defaults')->{$sidebar_key} }) {
            $tokens->{$sidebar_key}->query_param($col,
              var('sidebar_defaults')->{$sidebar_key}->{$col});
        }

        # 修复插件模板变量仅为path+query
        $tokens->{$sidebar_key} = $tokens->{$sidebar_key}->path_query;
    }

    # 来自NetAddr::MAC的MAC格式化助手
    $tokens->{mac_format_call} = 'as_'. lc(param('mac_format'))
      if param('mac_format');

    # 允许很长的端口列表
    $Template::Directive::WHILE_MAX = 10_000;

    # 允许带有前导下划线的哈希键
    $Template::Stash::PRIVATE = undef;
};

# 防止Template::AutoFilter对CSV输出采取行动
hook 'before_template' => sub {
    my $template_engine = engine 'template';
    if (not request->is_ajax
        and header('Content-Type')
        and header('Content-Type') eq 'text/comma-separated-values' ) {

        $template_engine->{config}->{AUTO_FILTER} = 'none';
        $template_engine->init();
    }
    # debug $template_engine->{config}->{AUTO_FILTER};
};
hook 'after_template_render' => sub {
    my $template_engine = engine 'template';
    if (not request->is_ajax
        and header('Content-Type')
        and header('Content-Type') eq 'text/comma-separated-values' ) {

        $template_engine->{config}->{AUTO_FILTER} = 'html_entity';
        $template_engine->init();
    }
    # debug $template_engine->{config}->{AUTO_FILTER};
};

# 支持报告API，这是JSON中的基本表结果
hook before_layout_render => sub {
  my ($tokens, $html_ref) = @_;
  return unless request_is_api_report or request_is_api_search;

  if (ref {} eq ref $tokens and exists $tokens->{results}) {
      ${ $html_ref } = to_json $tokens->{results};
  }
  elsif (ref {} eq ref $tokens) {
      map {delete $tokens->{$_}}
           grep {not blessed $tokens->{$_} or not $tokens->{$_}->isa('App::Netdisco::DB::ResultSet')}
                keys %$tokens;

      visit( $tokens, sub {
          my ( $key, $valueref ) = @_;
          $$valueref = [$$valueref->hri->all]
            if blessed $$valueref and $$valueref->isa('App::Netdisco::DB::ResultSet');
      });

      ${ $html_ref } = to_json $tokens;
  }
  else {
      ${ $html_ref } = '[]';
  }
};

# 修复Swagger插件奇怪响应体的变通方法
hook 'after' => sub {
    my $r = shift; # 一个Dancer::Response

    if (request->path =~ m{/swagger\.json} and
        request->path eq uri_for('/swagger.json')->path
          and ref {} eq ref $r->content) {
        my $spec = dclone $r->content;

        if (vars->{'tenant'}) {
            my $base = setting('path');
            my $tenant = '/t/' . vars->{'tenant'};
            $tenant = ($base . $tenant) if $base ne '/';
            $tenant .= '/' if $base eq '/';

            foreach my $path (sort keys %{ $spec->{paths} }) {
                (my $newpath = $path) =~ s/^$base/$tenant/;
                $spec->{paths}->{$newpath} = delete $spec->{paths}->{$path};
            }
        }

        $r->content( to_json( $spec ) );
        header('Content-Type' => 'application/json');
    }

    # 而不是设置序列化器
    # 并且处理一些插件在搜索失败时只返回undef的情况
    if (request_is_api) {
        header('Content-Type' => 'application/json');
        $r->content( $r->content || '[]' );
    }
};

# 设置swagger API
my $swagger = Dancer::Plugin::Swagger->instance;
my $swagger_doc = $swagger->doc;

$swagger_doc->{consumes} = 'application/json';
$swagger_doc->{produces} = 'application/json';
$swagger_doc->{tags} = [
  {name => 'General',
    description => 'Log in and Log out'},
  {name => 'Search',
    description => 'Search Operations'},
  {name => 'Objects',
    description => 'Device, Port, and associated Node Data'},
  {name => 'Reports',
    description => 'Canned and Custom Reports'},
  {name => 'Queue',
    description => 'Operations on the Job Queue'},
];

$swagger_doc->{securityDefinitions} = {
  APIKeyHeader =>
    { type => 'apiKey', name => 'Authorization', in => 'header' },
  BasicAuth =>
    { type => 'basic'  },
};
$swagger_doc->{security} = [ { APIKeyHeader => [] } ];

if (setting('trust_x_remote_user')) {
    foreach my $path (keys %{ $swagger_doc->{paths} }) {
        foreach my $method (keys %{ $swagger_doc->{paths}->{$path} }) {
            unshift @{ $swagger_doc->{paths}->{$path}->{$method}->{parameters} }, {
              name => 'X-REMOTE_USER',
              description => 'API client user name',
              in => 'header',
              required => false,
              type => 'string',
            };
        }
    }
}

# 手动安装Swagger UI路由，因为插件不处理非根主机
# 所以我们不能使用show_ui(1)
my $swagger_base = config->{plugins}->{Swagger}->{ui_url};

get $swagger_base => sub {
    Dancer::Plugin::Swagger->instance->doc->{schemes} = [ request->scheme ];
    redirect uri_for($swagger_base)->path
      . '/?url=' . uri_for('/swagger.json')->path;
};

get $swagger_base.'/' => sub {
    Dancer::Plugin::Swagger->instance->doc->{schemes} = [ request->scheme ];
    # 用户可能最初请求/swagger-ui/（插件不处理这个）
    params->{url} or redirect uri_for($swagger_base)->path;
    send_file( 'swagger-ui/index.html' );
};

# 天哪，插件使用system_path，我们不想去那里
get $swagger_base.'/**' => sub {
    Dancer::Plugin::Swagger->instance->doc->{schemes} = [ request->scheme ];
    send_file( join '/', 'swagger-ui', @{ (splat())[0] } );
};

# 从CSV响应中删除空行
# 这使得编写模板更加直接！
hook 'after' => sub {
    my $r = shift; # 一个Dancer::Response

    if ($r->content_type and $r->content_type eq 'text/comma-separated-values') {
        my @newlines = ();
        my @lines = split m/\n/, $r->content;

        foreach my $line (@lines) {
            push @newlines, $line if $line !~ m/^\s*$/;
        }

        $r->content(join "\n", @newlines);
    }
};

# 支持租户
any qr{^/t/(?<tenant>[^/]+)/?$} => sub {
    my $capture = captures;
    var tenant => $capture->{'tenant'};
    forward '/';
};
any '/t/*/**' => sub {
    my ($tenant, $path) = splat;
    var tenant => $tenant;
    forward (join '/', '', @$path, (request->path =~ m{/$} ? '' : ()));
};

any qr{.*} => sub {
    var('notfound' => true);
    status 'not_found';
    template 'index', {}, { layout => 'main' };
};

true;
