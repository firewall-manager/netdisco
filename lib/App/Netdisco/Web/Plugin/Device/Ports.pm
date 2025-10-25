# Netdisco 设备端口管理插件
# 此模块提供设备端口的查看、过滤和管理功能，包括端口状态、VLAN、节点连接等信息
package App::Netdisco::Web::Plugin::Device::Ports;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::Permission 'acl_matches';
use App::Netdisco::Util::Port qw/port_acl_service port_acl_pvid port_acl_name/;
use App::Netdisco::Util::Web (); # 用于端口排序功能
use App::Netdisco::Web::Plugin;

use List::MoreUtils 'singleton';

# 注册设备标签页 - 端口管理页面，支持CSV导出
register_device_tab({ tag => 'ports', label => 'Ports', provides_csv => 1 });

# 设备端口查询路由 - 需要用户登录，支持描述（名称）匹配
get '/ajax/content/device/ports' => require_login sub {
    # 获取查询参数
    my $q = param('q');                    # 设备查询参数
    my $prefer = param('prefer');          # 搜索偏好：端口、名称或VLAN
    $prefer = ''
      unless defined $prefer and $prefer =~ m/^(?:port|name|vlan)$/;

    # 根据设备标识查找设备，如果找不到则返回错误
    my $device = schema(vars->{'tenant'})->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);
    
    # 获取设备端口数据，包括属性和自定义字段
    my $set = $device->ports->with_properties->with_custom_fields;

    # 如果请求了端口过滤，则进行细化搜索
    my $f = param('f');
    if ($f) {
        # VLAN过滤：只接受数字VLAN ID
        if (($prefer eq 'vlan') or (not $prefer and $f =~ m/^\d+$/)) {
            return unless $f =~ m/^\d+$/;
        }
        else {
            # 部分匹配模式：处理通配符
            if (param('partial')) {
                # 将通配符转换为SQL格式
                $f =~ s/\*/%/g;
                $f =~ s/\?/_/g;
                # 在参数边界设置通配符
                if ($f !~ m/[%_]/) {
                    $f =~ s/^\%*/%/;
                    $f =~ s/\%*$/%/;
                }
                # 启用ILIKE操作符
                $f = { (param('invert') ? '-not_ilike' : '-ilike') => $f };
            }
            # 反转匹配模式
            elsif (param('invert')) {
                $f = { '!=' => $f };
            }

            # 端口或描述匹配
            if (($prefer eq 'port') or not $prefer and
                $set->search({-or => ['me.port' => $f, 'me.descr' => $f]})->count) {

                $set = $set->search({
                  -or => [
                    'me.port' => $f,      # 端口号匹配
                    'me.descr' => $f,      # 描述匹配
                    'me.slave_of' => $f,   # 从属端口匹配
                  ],
                });
            }
            # 端口名称匹配
            else {
                $set = $set->search({'me.name' => $f});
                return unless $set->count;
            }
        }
    }

    # 如果请求了端口状态过滤，则进行状态过滤
    my %port_state = map {$_ => 1}
      (ref [] eq ref param('port_state') ? @{param('port_state')}
        : param('port_state') ? param('port_state') : ());

    return unless scalar keys %port_state;

    # 处理空闲端口过滤
    if (exists $port_state{free}) {
        if (scalar keys %port_state == 1) {
            # 只显示空闲端口
            $set = $set->only_free_ports({
              age_num => (param('age_num') || 3),      # 空闲时间数量
              age_unit => (param('age_unit') || 'months')  # 空闲时间单位
            });
        }
        else {
            # 包含空闲状态信息
            $set = $set->with_is_free({
              age_num => (param('age_num') || 3),
              age_unit => (param('age_unit') || 'months')
            });
        }
        delete $port_state{free};
        # 显示空闲端口需要显示关闭端口
        ++$port_state{down};
    }

    # 根据端口状态组合过滤
    if (scalar keys %port_state < 3) {
        my @combi = ();

        # 添加运行状态过滤条件
        push @combi, {'me.up' => 'up'}
          if exists $port_state{up};
        push @combi, {'me.up_admin' => 'up', 'me.up' => { '!=' => 'up'}}
          if exists $port_state{down};
        push @combi, {'me.up_admin' => { '!=' => 'up'}}
          if exists $port_state{shut};

        $set = $set->search({-or => \@combi});
    }

    # 到目前为止只有基本的设备端口数据
    # 现在开始根据选择的列/选项连接表

    # 获取端口上的VLAN信息
    # 除非设置了c_vmember或VLAN过滤，否则保持查询休眠（延迟加载）
    my $vlans = $set->search(
      { param('p_hide1002') ?
        (-or => ['port_vlans.vlan' => {'<', '1002'},    # 隐藏1002-1005 VLAN
                 'port_vlans.vlan' => {'>', '1005'}]) : ()
      }, {
      select => [
        'port',
        { count     => 'port_vlans.vlan', -as => 'vlan_count' },  # VLAN数量
        { array_agg => \q{port_vlans.vlan ORDER BY port_vlans.vlan}, -as => 'vlan_set' },  # VLAN集合
        { array_agg => \q{COALESCE(NULLIF(vlan_entry.description,''), vlan_entry.vlan::text) ORDER BY vlan_entry.vlan}, -as => 'vlan_name_set' },  # VLAN名称集合
      ],
      join => {'port_vlans' => 'vlan_entry'},
      group_by => 'me.port',
    });

    # 如果需要VLAN成员信息，则执行查询并构建映射
    if (param('c_vmember') or ($prefer eq 'vlan') or (not $prefer and $f =~ m/^\d+$/)) {
        $vlans = { map {(
          $_->port => {
            # DBIC足够智能，知道这应该是一个数组引用 :)
            vlan_count => $_->get_column('vlan_count'),
            vlan_set   => $_->get_column('vlan_set'),
            vlan_name_set => $_->get_column('vlan_name_set'),
          },
        )} $vlans->all };
    }

    # 如果需要VLAN名称，则连接原生VLAN表
    if (param('p_vlan_names')) {
        $set = $set->search({}, {
          'join' => 'native_vlan',
          '+select' => [qw/native_vlan.description/],
          '+as'     => [qw/native_vlan_name/],
        });
    }

    # 获取聚合主端口状态（自连接）
    $set = $set->search({}, {
      'join' => 'agg_master',
      '+select' => [qw/agg_master.up_admin agg_master.up/],
      '+as'     => [qw/agg_master_up_admin agg_master_up/],
    });

    # 如果需要最后更改时间，则确保查询请求格式化的时间戳
    $set = $set->with_times if param('c_lastchange');

    # 确定我们感兴趣的节点类型
    my $nodes_name = (param('n_archived') ? 'nodes' : 'active_nodes');
    $nodes_name .= '_with_age' if param('n_age');

    # 确定IP地址类型
    my $ips_name = ((param('n_ip4') and param('n_ip6')) ? 'ips'
                   : param('n_ip4') ? 'ip4s'
                   : 'ip6s');

    # 如果需要节点信息，则获取连接的节点数据
    if (param('c_nodes')) {
        # 检索活动/所有连接的节点（如果请求）
        $set = $set->search({}, { prefetch => [{$nodes_name => $ips_name}] });
        $set = $set->search({}, { order_by => ["${nodes_name}.vlan", "${nodes_name}.mac", "${ips_name}.ip"] });

        # 检索无线SSID（如果请求）
        $set = $set->search({}, { prefetch => [{$nodes_name => 'wireless'}] })
          if param('n_ssid');

        # 检索NetBIOS信息（如果请求）
        $set = $set->search({}, { prefetch => [{$nodes_name => 'netbios'}] })
          if param('n_netbios');

        # 检索厂商信息（如果请求）
        $set = $set->search({}, { prefetch => [{$nodes_name => 'manufacturer'}] })
          if param('n_vendor');
    }

    # 检索SSID信息（如果请求）
    $set = $set->search({}, { prefetch => 'ssid' })
      if param('c_ssid');

    # 检索PoE信息（如果请求）
    $set = $set->search({}, { prefetch => 'power' })
      if param('c_power');

    # 检索邻居设备信息（如果请求）
    $set = $set->search({}, {
      join => 'neighbor_alias',
      '+select' => ['neighbor_alias.ip', 'neighbor_alias.dns'],
      '+as'     => ['neighbor_ip', 'neighbor_dns'],
    }) if param('c_neighbors');

    # 如果请求，也获取远程LLDP清单
    $set = $set->with_remote_inventory if param('n_inventory');

    # 执行查询
    my @results = $set->all;

    # 使用现有聚合查询过滤标记VLAN
    # 这比连接膨胀更好
    if (($prefer eq 'vlan') or (not $prefer and $f =~ m/^\d+$/)) {
      if (param('invert')) {
        # 反转过滤：排除匹配的VLAN
        @results = grep {
            (!defined $_->vlan or $_->vlan ne $f)
              and
            (0 == scalar grep {defined and $_ ne $f} @{ $vlans->{$_->port}->{vlan_set} })
        } @results;
      }
      else {
        # 正常过滤：包含匹配的VLAN
        @results = grep {
            (defined $_->vlan and $_->vlan eq $f)
              or
            (scalar grep {defined and $_ eq $f} @{ $vlans->{$_->port}->{vlan_set} })
        } @results;
      }
    }

    # 过滤隐藏的端口
    if (not param('p_include_hidden')) {
        my $port_map = {};
        my %to_hide  = ();

        # 构建端口映射
        map { push @{ $port_map->{$_->port} }, $_ }
             grep { $_->port }
             @results;

        map { push @{ $port_map->{$_->port} }, $_ }
            grep { $_->port }
            $device->device_ips()->all;

        # 根据配置隐藏端口
        foreach my $map (@{ setting('hide_deviceports')}) {
            next unless ref {} eq ref $map;

            foreach my $key (sort keys %$map) {
                # 左侧匹配设备，右侧匹配端口
                next unless $key and $map->{$key};
                next unless acl_matches($device, $key);

                foreach my $port (sort keys %$port_map) {
                    next unless acl_matches($port_map->{$port}, $map->{$key});
                    ++$to_hide{$port};
                }
            }
        }

        # 过滤掉隐藏的端口
        @results = grep { ! exists $to_hide{$_->port} } @results;
    }

    # 空集合会显示"无记录"消息
    return unless scalar @results;

    # 可折叠的子接口组处理
    my %port_has_dot_zero = ();      # 端口是否有.0子接口
    my %port_subinterface_count = (); # 端口子接口计数
    my $subinterfaces_match = (setting('subinterfaces_match') || qr/(.+)\.\d+/);

    # 处理子接口分组
    foreach my $port (@results) {
        if ($port->port =~ m/^${subinterfaces_match}$/) {
            my $parent = $1;
            next unless defined $parent;
            ++$port_subinterface_count{$parent};
            # 检查是否有.0子接口且类型匹配
            ++$port_has_dot_zero{$parent}
              if $port->port =~ m/\.0$/
                and ($port->type and $port->type =~ m/^(?:propVirtual|ieee8023adLag)$/i);
            $port->{subinterface_group} = $parent;
        }
    }

    # 设置父端口和子接口的属性
    foreach my $parent (keys %port_subinterface_count) {
        my $parent_port = [grep {$_->port eq $parent} @results]->[0];
        $parent_port->{has_subinterface_group} = true;
        # 如果只有.0子接口且类型匹配，则标记为仅有点零子接口
        $parent_port->{has_only_dot_zero_subinterface} = true
          if exists $port_has_dot_zero{$parent}
            and $port_subinterface_count{$parent} == 1
            and ($parent_port->type
              and $parent_port->type =~ m/^(?:ethernetCsmacd|ieee8023adLag)$/i);
        if ($parent_port->{has_only_dot_zero_subinterface}) {
            my $dotzero_port = [grep {$_->port eq "${parent}.0"} @results]->[0];
            $dotzero_port->{is_dot_zero_subinterface} = true;
        }
    }

    # 对端口进行排序
    @results = sort { &App::Netdisco::Util::Web::sort_port($a->port, $b->port) } @results;

    # 添加端口配置的ACL权限检查
    # 这包含合并的YAML和数据库配置
    if (param('c_admin') and user_has_role('port_control')) {
      # 原生VLAN更改权限
      map {$_->{port_acl_pvid} = port_acl_pvid($_, $device, logged_in_user)} @results;
      # 上下线和PoE权限
      map {$_->{port_acl_service} = port_acl_service($_, $device, logged_in_user)} @results;
      # 名称/描述更改权限
      map {$_->{port_acl_name} = ($_->{port_acl_service} || # 如果服务为真则此权限OK
                                  port_acl_name($_, $device, logged_in_user))} @results;
    }

    # 根据hide_tags设置过滤标签
    my @hide = @{ setting('hide_tags')->{'device_port'} };
    map { $_->{filtered_tags} = [ singleton (@{ $_->tags || [] }, @hide, @hide) ] } @results;

    # 美化端口运行速度显示
    use App::Netdisco::Util::Port 'to_speed';
    map { $_->{speed_running} = to_speed( $_->speed ) } @results;

    # 根据请求类型返回不同格式的数据
    if (request->is_ajax) {
        # AJAX请求：返回HTML模板
        template 'ajax/device/ports.tt', {
          results => \@results,    # 端口结果
          nodes => $nodes_name,   # 节点类型
          ips   => $ips_name,     # IP类型
          device => $device,      # 设备信息
          vlans  => $vlans,       # VLAN信息
        }, { layout => 'noop' };
    }
    else {
        # 非AJAX请求：返回CSV格式数据
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/device/ports_csv.tt', {
          results => \@results,
          nodes => $nodes_name,
          ips   => $ips_name,
          device => $device,
          vlans  => $vlans,
        }, { layout => 'noop' };
    }
};

true;
