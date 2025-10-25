package App::Netdisco::Web::TypeAhead;

# 自动完成Web模块
# 提供各种自动完成功能

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::Web (); # 用于端口排序
use HTML::Entities 'encode_entities';
use List::MoreUtils ();

# 后端自动完成AJAX路由
# 提供后端名称自动完成功能
ajax '/ajax/data/queue/typeahead/backend' => require_role admin => sub {
    my $q = quotemeta( param('query') || param('term') || param('backend') );
    # 获取唯一且排序的后端名称列表
    my @backends =
     grep { $q ? m/$q/ : true }
     List::MoreUtils::uniq
     sort
     grep { defined }
     schema(vars->{'tenant'})->resultset('DeviceSkip')->get_distinct_col('backend');

    content_type 'application/json';
    to_json \@backends;
};

# 用户名自动完成AJAX路由
# 提供管理员用户名自动完成功能
ajax '/ajax/data/queue/typeahead/username' => require_role admin => sub {
    my $q = quotemeta( param('query') || param('term') || param('username') );
    # 获取唯一且排序的用户名列表
    my @users =
     grep { $q ? m/$q/ : true }
     List::MoreUtils::uniq
     sort
     grep { defined }
     schema(vars->{'tenant'})->resultset('Admin')->get_distinct_col('username');

    content_type 'application/json';
    to_json \@users;
};

# 动作自动完成AJAX路由
# 提供作业动作自动完成功能
ajax '/ajax/data/queue/typeahead/action' => require_role admin => sub {
    my @actions = ();
    my @core_plugins = @{ setting('worker_plugins') || [] };
    my @user_plugins = @{ setting('extra_worker_plugins') || [] };

    # 扫描工作器插件获取动作
    foreach my $plugin (@user_plugins, @core_plugins) {
      $plugin =~ s/^X::/+App::NetdiscoX::Worker::Plugin::/;
      $plugin = 'App::Netdisco::Worker::Plugin::'. $plugin
        if $plugin !~ m/^\+/;
      $plugin =~ s/^\+//;

      next if $plugin =~ m/::Plugin::Internal::/;

      # 处理钩子插件
      if ($plugin =~ m/::Plugin::(Hook::[^:]+)/) {
          push @actions, lc $1;
          next;
      }

      next if $plugin =~ m/::Plugin::Hook$/;
      next unless $plugin =~ m/::Plugin::([^:]+)(?:::|$)/;

      push @actions, lc $1;
    }

    # 添加数据库中的动作
    push @actions,
     schema(vars->{'tenant'})->resultset('Admin')->get_distinct_col('action');

    my $q = quotemeta( param('query') || param('term') || param('action') );

    content_type 'application/json';
    to_json [
      grep { $q ? m/^$q/ : true }
      grep { defined }
      List::MoreUtils::uniq
      sort
      @actions
    ];
};

# 状态自动完成AJAX路由
# 提供作业状态自动完成功能
ajax '/ajax/data/queue/typeahead/status' => require_role admin => sub {
    my $q = quotemeta( param('query') || param('term') || param('status') );
    # 预定义的作业状态列表
    my @actions =
     grep { $q ? m/^$q/ : true }
     qw(Queued Running Done Info Deferred Error);

    content_type 'application/json';
    to_json \@actions;
};

# 设备名称自动完成AJAX路由
# 提供设备名称自动完成功能
ajax '/ajax/data/devicename/typeahead' => require_login sub {
    return '[]' unless setting('navbar_autocomplete');

    my $q = param('query') || param('term');
    # 搜索设备并限制结果数量
    my $set = schema(vars->{'tenant'})->resultset('Device')
      ->search_fuzzy($q)->search(undef, {rows => setting('max_typeahead_rows')});

    content_type 'application/json';
    # 返回设备DNS名称、名称或IP地址
    to_json [map {encode_entities($_->dns || $_->name || $_->ip)} $set->all];
};

# 设备IP自动完成AJAX路由
# 提供设备IP地址自动完成功能
ajax '/ajax/data/deviceip/typeahead' => require_login sub {
    my $q = param('query') || param('term');
    # 搜索设备并限制结果数量
    my $set = schema(vars->{'tenant'})->resultset('Device')
      ->search_fuzzy($q)->search(undef, {rows => setting('max_typeahead_rows')});

    my @data = ();
    while (my $d = $set->next) {
        my $label = $d->ip;
        # 如果有DNS名称或设备名称，则显示为"名称 (IP)"
        if ($d->dns or $d->name) {
            $label = sprintf '%s (%s)',
              ($d->dns || $d->name), $d->ip;
        }
        push @data, { label => $label, value => $d->ip };
    }

    content_type 'application/json';
    to_json \@data;
};

# 设备自动完成AJAX路由
# 提供设备自动完成功能，支持主机组和设备
ajax '/ajax/data/devices/typeahead' => require_login sub {
    my $q = param('device_rule') or return '[]';
    my $mode = param('aclhost') || 'ip';
    # 动态模式：根据查询内容判断是IP还是名称
    if ($mode eq 'dynamic') {
        $mode = (($q =~ m/^\d/ or $q =~ m/:/) ? 'ip' : 'name');
    }

    content_type 'application/json';
    my @data = ();

    # TODO 从数据库添加条目
    my @host_groups = sort {$a cmp $b}
                      grep {$_ !~ m/^synthesized_group_/}
                      keys %{ setting('host_groups')};

    # 如果查询以group:或acl:开头，则搜索主机组（排除合成的）
    if ($q =~ m/^(?:group:|acl:)/i) {
       return to_json [ map { 'group:'. $_ } @host_groups ];
    }

    # 检查主机组匹配
    if (scalar grep { $_ =~ m/\Q$q\E/i } @host_groups) {
        push @data, map { 'group:'. $_ }
                    grep { $_ =~ m/\Q$q\E/i } @host_groups
    }

    # 搜索设备
    my $set = schema(vars->{'tenant'})->resultset('Device')
      ->search_fuzzy($q)->search(undef, {rows => setting('max_typeahead_rows')});

    while (my $d = $set->next) {
        my $name = ($d->dns || $d->name);

        # 根据模式返回不同的数据格式
        if (not $name or $mode eq 'ip') {
            push @data, { value => $d->ip, label => ($name ? sprintf('%s (%s)', $d->ip, $name) : $d->ip)  };
        }
        elsif ($mode eq 'name') {
            push @data, { value => $name, label => sprintf('%s (%s)', $name, $d->ip) };
        }
    }

    return to_json \@data;
};

# 端口自动完成AJAX路由
# 提供设备端口自动完成功能
ajax '/ajax/data/port/typeahead' => require_login sub {
    my $dev  = param('dev1')  || param('dev2');
    my $port = param('port1') || param('port2');
    send_error('Missing device', 400) unless $dev;

    # 查找设备
    my $device = schema(vars->{'tenant'})->resultset('Device')
      ->find({ip => $dev});
    send_error('Bad device', 400) unless $device;

    # 获取设备端口
    my $set = $device->ports({},{order_by => 'port'});
    # 如果提供了端口参数，则进行模糊搜索
    $set = $set->search({port => { -ilike => "\%$port\%" }})
      if $port;

    # 构建结果，按端口排序
    my $results = [
      map  {{ label => (sprintf "%s (%s)", $_->port, ($_->name || '')), value => $_->port }}
      sort { &App::Netdisco::Util::Web::sort_port($a->port, $b->port) } $set->all
    ];

    content_type 'application/json';
    to_json \@$results;
};

# 子网自动完成AJAX路由
# 提供子网自动完成功能
ajax '/ajax/data/subnet/typeahead' => require_login sub {
    my $q = param('query') || param('term');
    # 如果没有通配符，则添加%
    $q = "$q\%" if $q !~ m/\%/;
    # 搜索子网
    my $nets = schema(vars->{'tenant'})->resultset('Subnet')->search(
           { 'me.net::text'  => { '-ilike' => $q }},
           { columns => ['net'], order_by => 'net', rows => setting('max_typeahead_rows') } );

    content_type 'application/json';
    to_json [map {$_->net} $nets->all];
};

true;
