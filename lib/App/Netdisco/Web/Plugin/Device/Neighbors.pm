# Netdisco 设备邻居关系管理插件
# 此模块提供网络拓扑图功能，包括设备邻居关系、网络地图和位置管理
package App::Netdisco::Web::Plugin::Device::Neighbors;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use List::Util 'first';
use List::MoreUtils ();
use HTML::Entities 'encode_entities';
use App::Netdisco::Util::Port 'to_speed';
use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;
use App::Netdisco::Web::Plugin;

# 注册设备标签页 - 网络地图页面
register_device_tab({ tag => 'netmap', label => 'Neighbors' });

# 网络地图页面路由 - 需要用户登录
ajax '/ajax/content/device/netmap' => require_login sub {
    content_type('text/html');
    template 'ajax/device/netmap.tt', {}, { layout => undef };
};

# 网络地图位置数据保存路由 - 需要用户登录
ajax '/ajax/data/device/netmappositions' => require_login sub {
    # 获取查询参数中的设备标识
    my $q = param('q');
    # 根据设备标识查找设备，如果找不到则返回错误
    my $qdev = schema(vars->{'tenant'})->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);

    # 获取位置数据参数
    my $p = param('positions') or send_error('Missing positions', 400);
    my $positions = from_json($p) or send_error('Bad positions', 400);
    send_error('Bad positions', 400) unless ref [] eq ref $positions;

    # 获取VLAN参数并验证
    my $vlan = param('vlan');
    undef $vlan if (defined $vlan and $vlan !~ m/^\d+$/);

    # 获取地图显示模式参数并验证
    my $mapshow = param('mapshow');
    return if !defined $mapshow or $mapshow !~ m/^(?:all|cloud|depth)$/;
    my $depth = param('depth') || 1;
    return if $depth !~ m/^\d+$/;

    # 获取用户选择的主机组列表
    my $hgroup = (ref [] eq ref param('hgroup') ? param('hgroup') : [param('hgroup')]);
    # 验证并过滤真实的主机组和命名主机组
    my @hgrplist = List::MoreUtils::uniq
                   grep { exists setting('host_group_displaynames')->{$_} }
                   grep { exists setting('host_groups')->{$_} }
                   grep { defined } @{ $hgroup };

    # 获取用户选择的位置组列表
    my $lgroup = (ref [] eq ref param('lgroup') ? param('lgroup') : [param('lgroup')]);
    my @lgrplist = List::MoreUtils::uniq grep { defined } @{ $lgroup };

    # 清理和验证位置数据
    my %clean = ();
    POSITION: foreach my $pos (@$positions) {
      next unless ref {} eq ref $pos;
      foreach my $k (qw/ID x y/) {
        next POSITION unless exists $pos->{$k};
        next POSITION unless $pos->{$k} =~ m/^[[:word:]\.-]+$/;
      }
      $clean{$pos->{ID}} = { x => $pos->{x}, y => $pos->{y} };
    }
    return unless scalar keys %clean;

    # 查找现有的位置记录
    my $posrow = schema(vars->{'tenant'})->resultset('NetmapPositions')->find({
      device => ($mapshow ne 'all' ? $qdev->ip : undef),
      depth  => ($mapshow eq 'depth' ? $depth : 0),
      host_groups => \[ '= ?', [host_groups => [sort @hgrplist]] ],
      locations   => \[ '= ?', [locations   => [sort @lgrplist]] ],
      vlan => ($vlan || 0),
    });

    # 更新现有记录或创建新记录
    if ($posrow) {
      $posrow->update({ positions => to_json(\%clean) });
    }
    else {
      schema(vars->{'tenant'})->resultset('NetmapPositions')->create({
        device => ($mapshow ne 'all' ? $qdev->ip : undef),
        depth  => ($mapshow eq 'depth' ? $depth : 0),
        host_groups => [sort @hgrplist],
        locations   => [sort @lgrplist],
        vlan => ($vlan || 0),
        positions => to_json(\%clean),
      });
    }
};

# 生成节点信息字符串的辅助函数
sub make_node_infostring {
  my $node = shift or return '';
  # 定义节点信息显示格式
  my $fmt = ('<b>%s</b> is %s <b>%s %s</b><br>running <b>%s %s</b><br>Serial: <b>%s</b><br>'
    .'Uptime: <b>%s</b><br>Location: <b>%s</b><br>Contact: <b>%s</b>');
  
  # 处理自定义字段
  my @field_values = ();
  if (ref [] eq ref setting('netmap_custom_fields')->{device}) {
      foreach my $field (@{ setting('netmap_custom_fields')->{device} }) {
          foreach my $config (@{ setting('custom_fields')->{device} }) {
              next unless $config->{'name'} and $config->{'name'} eq $field;

              next if $config->{json_list};
              next if acl_matches($node->ip, ($config->{no} || []));
              next unless acl_matches_only($node->ip, ($config->{only} || []));
              $fmt .= sprintf '<br>%s: <b>%%s</b>', ($config->{label} || ucfirst($config->{name}));
              push @field_values, ('cf_'. $config->{name});
          }
      }
  }

  # 格式化并返回节点信息字符串
  return sprintf $fmt, $node->ip,
    ((($node->vendor || '') =~ m/^[aeiou]/i) ? 'an' : 'a'),
    encode_entities(ucfirst($node->vendor || '')),
    (map {defined $_ ? encode_entities($_) : ''}
        map {$node->$_}
            (qw/model os os_ver serial uptime_age location contact/)),
    map {encode_entities($node->get_column($_) || '')} @field_values;
}

# 生成链路信息字符串的辅助函数
sub make_link_infostring {
  my $link = shift or return '';

  # 获取域名后缀设置
  my $domains = setting('domain_suffix');
  # 处理左侧设备名称，移除域名后缀
  (my $left_name = lc($link->{left_dns} || $link->{left_name} || $link->{left_ip})) =~ s/$domains//;
  # 处理右侧设备名称，移除域名后缀
  (my $right_name = lc($link->{right_dns} || $link->{right_name} || $link->{right_ip})) =~ s/$domains//;

  # 将端口和描述信息配对
  my @zipped = List::MoreUtils::zip6
    @{$link->{left_port}}, @{$link->{left_descr}},
    @{$link->{right_port}}, @{$link->{right_descr}};

  # 格式化并返回链路信息字符串
  return join '<br><br>', map { sprintf '<b>%s:%s</b> (%s)<br><b>%s:%s</b> (%s)',
    encode_entities($left_name), encode_entities($_->[0]), encode_entities(($_->[1] || 'no description')),
    encode_entities($right_name), encode_entities($_->[2]), encode_entities(($_->[3] || 'no description')) } @zipped;
}

# 网络地图数据获取路由 - 需要用户登录
get '/ajax/data/device/netmap' => require_login sub {
    # 获取查询参数中的设备标识
    my $q = param('q');
    # 根据设备标识查找设备，如果找不到则返回错误
    my $qdev = schema(vars->{'tenant'})->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);

    # 获取VLAN参数并验证
    my $vlan = param('vlan');
    undef $vlan if (defined $vlan and $vlan !~ m/^\d+$/);

    # 获取地图显示参数
    my $colorby = (param('colorby') || 'speed');  # 颜色依据：速度、主机组、位置组
    my $mapshow = (param('mapshow') || 'depth');  # 显示模式：全部、云、深度
    my $depth   = (param('depth')   || 1);         # 深度级别
    $mapshow = 'depth' if $mapshow !~ m/^(?:all|cloud|depth)$/;
    $mapshow = 'all' unless $qdev->in_storage;

    # 获取用户选择的主机组列表
    my $hgroup = (ref [] eq ref param('hgroup') ? param('hgroup') : [param('hgroup')]);
    # 验证并过滤真实的主机组和命名主机组
    my @hgrplist = List::MoreUtils::uniq
                   grep { exists setting('host_group_displaynames')->{$_} }
                   grep { exists setting('host_groups')->{$_} }
                   grep { defined } @{ $hgroup };

    # 获取用户选择的位置组列表
    my $lgroup = (ref [] eq ref param('lgroup') ? param('lgroup') : [param('lgroup')]);
    my @lgrplist = List::MoreUtils::uniq grep { defined } @{ $lgroup };

    # 初始化数据结构和变量
    my %ok_dev = ();      # 有效设备列表
    my %logvals = ();     # 日志值统计
    my %metadata = ();    # 元数据
    my %data = ( nodes => [], links => [] );  # 节点和链路数据
    my $domains = setting('domain_suffix');   # 域名后缀设置

    # 处理链路数据
    my %seen_link = ();
    # 查询设备链路，根据显示模式过滤
    my $links = schema(vars->{'tenant'})->resultset('Virtual::DeviceLinks')->search({
      (($mapshow eq 'depth' and $depth == 1) ? ( -or => [
          { left_ip  => $qdev->ip },
          { right_ip => $qdev->ip },
      ]) : ())
    }, { result_class => 'DBIx::Class::ResultClass::HashRefInflator' });

    # 处理每个链路
    while (my $link = $links->next) {
      # 查询按聚合速度降序排列，优先显示最高速度的链路
      # 如果链路不对称，这通常是"最佳"链路
      next if exists $seen_link{$link->{left_ip} ."\0". $link->{right_ip}}
           or exists $seen_link{$link->{right_ip} ."\0". $link->{left_ip}};

      # 添加链路到数据中
      push @{$data{'links'}}, {
        FROMID => $link->{left_ip},
        TOID   => $link->{right_ip},
        INFOSTRING => make_link_infostring($link),
        SPEED  => to_speed($link->{aggspeed}),
      };

      # 记录有效设备
      ++$ok_dev{$link->{left_ip}};
      ++$ok_dev{$link->{right_ip}};
      ++$seen_link{$link->{left_ip} ."\0". $link->{right_ip}};
    }

    # 根据LLDP云或深度过滤设备
    # 这是O(N^2)或更复杂的算法

    my %cloud = ($qdev->ip => 1);  # 云设备列表，从查询设备开始
    my $seen_cloud = scalar keys %cloud;
    my $passes = ($mapshow eq 'cloud' ? 999 : $depth);  # 云模式使用大量传递，深度模式使用指定深度

    # 云模式或深度模式的多层处理
    if ($mapshow eq 'cloud' or ($mapshow eq 'depth' and $depth > 1)) {
        while ($seen_cloud > 0 and $passes > 0) {
            --$passes;
            $seen_cloud = 0;

            # 遍历当前云中的每个设备
            foreach my $cip (keys %cloud) {
                foreach my $okip (keys %ok_dev) {
                    next if exists $cloud{$okip};

                    # 如果设备间有链路连接，添加到云中
                    if (exists $seen_link{$cip ."\0". $okip}
                        or exists $seen_link{$okip ."\0". $cip}) {

                        ++$cloud{$okip};
                        ++$seen_cloud;
                    }
                }
            }
        }
    }
    # 深度模式且深度为1时，直接使用有效设备
    elsif ($mapshow eq 'depth' and $depth == 1) {
        %cloud = %ok_dev;
    }

    # 处理设备（节点）数据

    # 查找位置记录
    my $posrow = schema(vars->{'tenant'})->resultset('NetmapPositions')->find({
      device => ($mapshow ne 'all' ? $qdev->ip : undef),
      depth  => ($mapshow eq 'depth' ? $depth : 0),
      host_groups => \[ '= ?', [host_groups => [sort @hgrplist]] ],
      locations   => \[ '= ?', [locations   => [sort @lgrplist]] ],
      vlan => ($vlan || 0),
    });
    # 获取保存的位置信息
    my $pos_for = from_json( $posrow ? $posrow->positions : '{}' );

    # 查询设备数据，包括吞吐量日志值
    my $devices = schema(vars->{'tenant'})->resultset('Device')->search({}, {
      '+select' => [\'floor(log(throughput.total))'], '+as' => ['log'],
      join => 'throughput', distinct => 1,
    })->with_times->with_custom_fields;

    # 根据VLAN过滤设备（全部或仅邻居）
    if ($vlan) {
      $devices = $devices->search(
        { 'port_vlans_filter.vlan' => $vlan },
        { join => 'port_vlans_filter' }
      );
    }

    # 处理每个设备
    DEVICE: while (my $device = $devices->next) {
      # 如果是邻居模式，使用%ok_dev过滤设备
      next DEVICE if ($device->ip ne $qdev->ip)
        and ($mapshow ne 'all')
        and (not $cloud{$device->ip}); # 只显示邻居但没有链路

      # 如果选择了位置，则按位置过滤
      next DEVICE if ((scalar @lgrplist) and ((!defined $device->location)
        or (0 == scalar grep {$_ eq $device->location} @lgrplist)));

      # 如果选择了主机组，则使用ACL过滤
      my $first_hgrp =
        first { acl_matches($device, setting('host_groups')->{$_}) } @hgrplist;
      next DEVICE if ((scalar @hgrplist) and (not $first_hgrp));

      # 重新设置first_hgroup为匹配设备的组（如果有）
      $first_hgrp = first { acl_matches($device, setting('host_groups')->{$_}) }
                          keys %{ setting('host_group_displaynames') || {} };

      # 统计日志值并处理设备名称
      ++$logvals{ $device->get_column('log') || 1 };
      (my $name = lc($device->dns || $device->name || $device->ip)) =~ s/$domains//;

      # 设置颜色查找表
      my %color_lkp = (
        speed => (($device->get_column('log') || 1) * 1000),  # 速度颜色
        hgroup => ($first_hgrp ?                              # 主机组颜色
          setting('host_group_displaynames')->{$first_hgrp} : 'Other'),
        lgroup => ($device->location || 'Other'),             # 位置组颜色
      );

      # 创建节点数据结构
      my $node = {
        ID => $device->ip,
        SIZEVALUE => (param('dynamicsize') ? $color_lkp{speed} : 3000),  # 节点大小
        ((exists $color_lkp{$colorby}) ? (COLORVALUE => $color_lkp{$colorby}) : ()),  # 颜色值
        (($device->ip eq $qdev->ip) ? (COLORVALUE => 'ROOTNODE') : ()),   # 根节点颜色
        LABEL => (param('showips') ? ($device->ip .' '. $name) : $name),  # 标签
        ORIG_LABEL => $name,                                               # 原始标签
        INFOSTRING => make_node_infostring($device),                       # 信息字符串
        LINK => uri_for('/device', {                                       # 链接
          tab => 'netmap',
          q => $device->ip,
          firstsearch => 'on',
        })->path_query,
      };

      # 如果设备有保存的位置，设置为固定位置
      if (exists $pos_for->{$device->ip}) {
        $node->{'fixed'} = 1;
        $node->{'x'} = $pos_for->{$device->ip}->{'x'};
        $node->{'y'} = $pos_for->{$device->ip}->{'y'};
      }
      else {
        ++$metadata{'newnodes'};  # 新节点计数
      }

      # 添加节点到数据中
      push @{$data{'nodes'}}, $node;
      # 设置中心节点
      $metadata{'centernode'} = $device->ip
        if $qdev and $qdev->in_storage and $device->ip eq $qdev->ip;
    }

    # 帮助获得合理的节点大小范围
    $metadata{'numsizes'} = scalar keys %logvals;

    # 返回JSON格式的地图数据
    content_type('application/json');
    to_json({ data => \%data, %metadata });
};

true;
