package App::Netdisco::Util::Device;

# 设备工具模块
# 提供支持Netdisco应用程序各个部分的辅助子程序

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;

use List::MoreUtils       ();
use File::Spec::Functions qw(catdir catfile);
use File::Path 'make_path';
use Scalar::Util 'blessed';
use NetAddr::IP;

use base 'Exporter';
our @EXPORT    = ();
our @EXPORT_OK = qw/
  get_device
  delete_device
  renumber_device
  match_to_setting
  is_discoverable is_discoverable_now
  is_arpnipable   is_arpnipable_now
  is_macsuckable  is_macsuckable_now
  get_denied_actions
  /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Device

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 get_device( $ip )

Given an IP address, returns a L<DBIx::Class::Row> object for the Device in
the Netdisco database. The IP can be for any interface on the device.

If for any reason C<$ip> is already a C<DBIx::Class> Device object, then it is
simply returned. If C<$ip> can C<addr> or C<ip> then those methods are called
to get an IP address to locate in the database.

If the device or interface IP is not known to Netdisco a new Device object is
created for the IP, and returned. This object is in-memory only and not yet
stored to the database.

=cut

# 获取设备对象
# 根据IP地址返回Netdisco数据库中设备的DBIx::Class::Row对象
sub get_device {
  my $ip = shift;
  return unless $ip;

  # 如果已经是设备对象，直接返回
  if (blessed $ip) {
    return $ip if blessed $ip eq 'App::Netdisco::DB::Result::Device';

    # 尝试获取IP地址
    if ($ip->can('addr')) {
      $ip = $ip->addr;
    }
    elsif ($ip->can('ip')) {
      $ip = $ip->ip;
    }
    else {
      die sprintf 'unknown class %s passed to get_device', blessed $ip;
    }
  }

  die 'reference passed to get_device' if ref $ip;

  # 如果一个设备的管理IP被另一个设备使用，
  # 我们首先尝试获取IP作为管理接口的精确匹配
  my $alias = schema(vars->{'tenant'})->resultset('DeviceIp')->find($ip, $ip)
    || schema(vars->{'tenant'})->resultset('DeviceIp')->search({alias => $ip})->first;
  $ip = $alias->ip if defined $alias;

  return schema(vars->{'tenant'})->resultset('Device')->with_times->find_or_new({ip => $ip});
}

=head2 delete_device( $ip, $archive? )

Given an IP address, deletes the device from Netdisco, including all related
data such as logs and nodes. If the C<$archive> parameter is true, then nodes
will be maintained in an archive state.

Returns true if the transaction completes, else returns false.

=cut

# 删除设备
# 根据IP地址从Netdisco中删除设备，包括所有相关数据如日志和节点
sub delete_device {
  my ($ip, $archive) = @_;
  my $device = get_device($ip) or return 0;
  return 0 if not $device->in_storage;

  my $happy = 0;
  schema(vars->{'tenant'})->txn_do(sub {

    # 将删除所有相关数据...
    schema(vars->{'tenant'})->resultset('Device')->search({ip => $device->ip})->delete({archive_nodes => $archive});

    $happy = 1;
  });

  return $happy;
}

=head2 renumber_device( $current_ip, $new_ip )

Will update all records in Netdisco referring to the device with
C<$current_ip> to use C<$new_ip> instead, followed by renumbering the
device itself.

Returns true if the transaction completes, else returns false.

=cut

# 重新编号设备
# 将Netdisco中引用具有当前IP的设备的所有记录更新为使用新IP
sub renumber_device {
  my ($ip, $new_ip) = @_;
  my $device = get_device($ip) or return 0;
  return 0 if not $device->in_storage;

  my $happy = 0;
  schema(vars->{'tenant'})->txn_do(sub {
    $device->renumber($new_ip) or die "cannot renumber to: $new_ip";    # 回滚

    # 记录用户日志
    schema(vars->{'tenant'})->resultset('UserLog')->create({
      username => session('logged_in_user'),
      userip   => scalar eval { request->remote_address },
      event    => (sprintf "Renumber device %s to %s", $ip, $new_ip),
    });

    $happy = 1;
  });

  return $happy;
}

=head2 match_to_setting( $type, $setting_name )

Given a C<$type> (which may be any text value), returns true if any of the
list of regular expressions in C<$setting_name> is matched, otherwise returns
false.

=cut

# 匹配设置
# 根据类型和设置名称进行正则表达式匹配
sub match_to_setting {
  my ($type, $setting_name) = @_;
  return 0 unless $type and $setting_name;
  return (scalar grep { $type =~ m/$_/ } @{setting($setting_name) || []});
}

# 内部辅助函数：记录调试消息并返回0
sub _bail_msg { debug $_[0]; return 0; }

=head2 is_discoverable( $ip, [$device_type, \@device_capabilities]? )

Given an IP address, returns C<true> if Netdisco on this host is permitted by
the local configuration to discover the device.

The configuration items C<discover_no> and C<discover_only> are checked
against the given IP.

If C<$device_type> is also given, then C<discover_no_type> will be checked.
Also respects C<discover_phones> and C<discover_waps> if either are set to
false.

Also checks if the device is a pseudo device and no offline cache exists.

Returns false if the host is not permitted to discover the target device.

=cut

# 检查设备是否可发现
# 根据IP地址返回Netdisco是否被本地配置允许发现该设备
sub is_discoverable {
  my ($ip, $remote_type, $remote_cap) = @_;
  my $device = get_device($ip) or return 0;
  $remote_type ||= '';
  $remote_cap  ||= [];

  # 检查伪设备是否有离线缓存
  return _bail_msg("is_discoverable: $device is pseudo-device without offline cache")
    if $device->is_pseudo and not $device->oids->count;

  # 检查WAP平台匹配但未启用WAP发现
  return _bail_msg("is_discoverable: $device matches wap_platforms but discover_waps is not enabled")
    if ((not setting('discover_waps')) and match_to_setting($remote_type, 'wap_platforms'));

  # 检查WAP能力匹配但未启用WAP发现
  return _bail_msg("is_discoverable: $device matches wap_capabilities but discover_waps is not enabled")
    if ((not setting('discover_waps')) and (scalar grep { match_to_setting($_, 'wap_capabilities') } @$remote_cap));

  # 检查电话平台匹配但未启用电话发现
  return _bail_msg("is_discoverable: $device matches phone_platforms but discover_phones is not enabled")
    if ((not setting('discover_phones')) and match_to_setting($remote_type, 'phone_platforms'));

  # 检查电话能力匹配但未启用电话发现
  return _bail_msg("is_discoverable: $device matches phone_capabilities but discover_phones is not enabled")
    if ((not setting('discover_phones')) and (scalar grep { match_to_setting($_, 'phone_capabilities') } @$remote_cap));

  # 检查设备类型是否在禁止发现列表中
  return _bail_msg("is_discoverable: $device matched discover_no_type")
    if (match_to_setting($remote_type, 'discover_no_type'));

  # 检查设备是否匹配禁止发现规则
  return _bail_msg("is_discoverable: $device matched discover_no") if acl_matches($device, 'discover_no');

  # 检查设备是否匹配仅发现规则
  return _bail_msg("is_discoverable: $device failed to match discover_only")
    unless acl_matches_only($device, 'discover_only');

  return 1;
}

=head2 is_discoverable_now( $ip, $device_type? )

Same as C<is_discoverable>, but also compares the C<last_discover> field
of the C<device> to the C<discover_min_age> configuration.

Returns false if the host is not permitted to discover the target device.

=cut

# 检查设备现在是否可发现
# 与is_discoverable相同，但还会比较设备的last_discover字段与discover_min_age配置
sub is_discoverable_now {
  my ($ip, $remote_type) = @_;
  my $device = get_device($ip) or return 0;

  # 检查是否满足最小发现间隔要求
  if (  $device->in_storage
    and $device->since_last_discover
    and setting('discover_min_age')
    and $device->since_last_discover < setting('discover_min_age')) {

    return _bail_msg("is_discoverable: $device last discover < discover_min_age");
  }

  return is_discoverable(@_);
}

=head2 is_arpnipable( $ip )

Given an IP address, returns C<true> if Netdisco on this host is permitted by
the local configuration to arpnip the device.

The configuration items C<arpnip_no> and C<arpnip_only> are checked
against the given IP.

Also checks if the device reports layer 3 capability, or matches
C<force_arpnip> or C<ignore_layers>.

Returns false if the host is not permitted to arpnip the target device.

=cut

# 检查设备是否可进行ARP扫描
# 根据IP地址返回Netdisco是否被本地配置允许对设备进行arpnip操作
sub is_arpnipable {
  my $ip     = shift;
  my $device = get_device($ip) or return 0;

  # 检查设备是否有第3层能力
  return _bail_msg("is_arpnipable: $device has no layer 3 capability")
    if ($device->in_storage()
    and not($device->has_layer(3) or acl_matches($device, 'force_arpnip') or acl_matches($device, 'ignore_layers')));

  # 检查设备是否匹配禁止ARP扫描规则
  return _bail_msg("is_arpnipable: $device matched arpnip_no") if acl_matches($device, 'arpnip_no');

  # 检查设备是否匹配仅ARP扫描规则
  return _bail_msg("is_arpnipable: $device failed to match arpnip_only")
    unless acl_matches_only($device, 'arpnip_only');

  return 1;
}

=head2 is_arpnipable_now( $ip )

Same as C<is_arpnipable>, but also compares the C<last_arpnip> field
of the C<device> to the C<arpnip_min_age> configuration.

Returns false if the host is not permitted to arpnip the target device.

=cut

# 检查设备现在是否可进行ARP扫描
# 与is_arpnipable相同，但还会比较设备的last_arpnip字段与arpnip_min_age配置
sub is_arpnipable_now {
  my ($ip) = @_;
  my $device = get_device($ip) or return 0;

  # 检查是否满足最小ARP扫描间隔要求
  if (  $device->in_storage
    and $device->since_last_arpnip
    and setting('arpnip_min_age')
    and $device->since_last_arpnip < setting('arpnip_min_age')) {

    return _bail_msg("is_arpnipable: $device last arpnip < arpnip_min_age");
  }

  return is_arpnipable(@_);
}

=head2 is_macsuckable( $ip )

Given an IP address, returns C<true> if Netdisco on this host is permitted by
the local configuration to macsuck the device.

The configuration items C<macsuck_no> and C<macsuck_only> are checked
against the given IP.

Also checks if the device reports layer 2 capability, or matches
C<force_macsuck> or C<ignore_layers>.

Returns false if the host is not permitted to macsuck the target device.

=cut

# 检查设备是否可进行MAC地址收集
# 根据IP地址返回Netdisco是否被本地配置允许对设备进行macsuck操作
sub is_macsuckable {
  my $ip     = shift;
  my $device = get_device($ip) or return 0;

  # 检查设备是否有第2层能力
  return _bail_msg("is_macsuckable: $device has no layer 2 capability")
    if ($device->in_storage()
    and not($device->has_layer(2) or acl_matches($device, 'force_macsuck') or acl_matches($device, 'ignore_layers')));

  # 检查设备是否匹配禁止MAC收集规则
  return _bail_msg("is_macsuckable: $device matched macsuck_no") if acl_matches($device, 'macsuck_no');

  # 检查设备是否匹配不支持MAC收集规则
  return _bail_msg("is_macsuckable: $device matched macsuck_unsupported")
    if acl_matches($device, 'macsuck_unsupported');

  # 检查设备是否匹配仅MAC收集规则
  return _bail_msg("is_macsuckable: $device failed to match macsuck_only")
    unless acl_matches_only($device, 'macsuck_only');

  return 1;
}

=head2 is_macsuckable_now( $ip )

Same as C<is_macsuckable>, but also compares the C<last_macsuck> field
of the C<device> to the C<macsuck_min_age> configuration.

Returns false if the host is not permitted to macsuck the target device.

=cut

# 检查设备现在是否可进行MAC地址收集
# 与is_macsuckable相同，但还会比较设备的last_macsuck字段与macsuck_min_age配置
sub is_macsuckable_now {
  my ($ip) = @_;
  my $device = get_device($ip) or return 0;

  # 检查是否满足最小MAC收集间隔要求
  if (  $device->in_storage
    and $device->since_last_macsuck
    and setting('macsuck_min_age')
    and $device->since_last_macsuck < setting('macsuck_min_age')) {

    return _bail_msg("is_macsuckable: $device last macsuck < macsuck_min_age");
  }

  return is_macsuckable(@_);
}

=head2 get_denied_actions( $device )

Checks configured ACLs for the device on this backend and returns list
of actions which are denied.

=cut

# 获取被拒绝的操作列表
# 检查此后端上设备的配置ACL并返回被拒绝的操作列表
sub get_denied_actions {
  my $device     = shift;
  my @badactions = ();
  return @badactions unless $device;
  $device = get_device($device);    # 可能是空操作，但在is_*中已经完成

  # 处理伪设备
  if ($device->is_pseudo) {

    # 总是允许伪设备执行contact|location|portname|snapshot|delete
    # 另外，如果有快照缓存，is_discoverable将允许它们执行所有其他发现和高优先级操作
    push @badactions,
      ('discover', grep { $_ !~ m/^(?:contact|location|portname|snapshot|delete)$/ } @{setting('job_prio')->{high}})
      if not is_discoverable($device);
  }
  else {
    # #1335 总是允许删除操作运行
    push @badactions, ('discover', grep { $_ !~ m/^(?:delete)$/ } @{setting('job_prio')->{high}})
      if not is_discoverable($device);
  }

  # 检查MAC收集操作
  push @badactions, (qw/macsuck nbtstat/) if not is_macsuckable($device);

  # 检查ARP扫描操作
  push @badactions, 'arpnip' if not is_arpnipable($device);

  # 为具有ACL的调度条目添加伪操作
  my $schedule = setting('schedule') || {};
  foreach my $label (keys %$schedule) {
    my $sched = $schedule->{$label} || next;
    next unless $sched->{only} or $sched->{no};

    my $action        = $sched->{action} || $label;
    my $pseudo_action = "scheduled-$label";

    # 如果此操作在全局配置中被拒绝，则调度不应运行
    if (scalar grep { $_ eq $action } @badactions) {
      push @badactions, $pseudo_action;
      next;
    }

    my $net = NetAddr::IP->new($sched->{device});
    next if ($sched->{device} and (!$net or $net->num == 0 or $net->addr eq '0.0.0.0'));

    # 检查调度ACL规则
    push @badactions, $pseudo_action if $sched->{device} and not acl_matches_only($device, $net->cidr);
    push @badactions, $pseudo_action if $sched->{no}     and acl_matches($device, $sched->{no});
    push @badactions, $pseudo_action if $sched->{only}   and not acl_matches_only($device, $sched->{only});
  }

  return List::MoreUtils::uniq @badactions;
}

1;
