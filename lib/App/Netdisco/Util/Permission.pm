package App::Netdisco::Util::Permission;

# 权限控制工具模块
# 支持Netdisco应用程序各个部分的辅助子程序

use strict;
use warnings;
use Dancer qw/:syntax :script/;

use Scalar::Util qw/blessed reftype/;
use NetAddr::IP::Lite ':lower';
use Algorithm::Cron;

use App::Netdisco::Util::DNS 'hostname_from_ip';

use base 'Exporter';
our @EXPORT      = ();
our @EXPORT_OK   = qw/check_acl check_acl_no check_acl_only acl_matches acl_matches_only/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Permission

=head1 DESCRIPTION

Helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 acl_matches( $ip | $object | \%hash | \@item_list, $setting_name | $acl_entry | \@acl )

Given an IP address, object instance, or hash, returns true if the
configuration setting C<$setting_name> matches, else returns false.

Usage of this function is strongly advised to be of the form:

 QUIT/SKIP IF acl_matches

The function fails safe, so if the content of the setting or ACL is undefined
or an empty string, then C<acl_matches> also returns true.

If C<$setting_name> is a valid setting, then it will be resolved to the access
control list, else we assume you passed an ACL entry or ACL.

See L<the Netdisco wiki|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
for details of what C<$acl> may contain.

=cut

# 检查ACL匹配
# 给定IP地址、对象实例或哈希，如果配置设置匹配则返回true，否则返回false
sub acl_matches {
  my ($thing, $setting_name) = @_;

  # 故障安全，未定义配置应返回true
  return true unless $thing and $setting_name;
  my $config = (exists config->{"$setting_name"} ? setting($setting_name) : $setting_name);
  return check_acl($thing, $config);
}

=head2 check_acl_no( $ip | $object | \%hash | \@item_list, $setting_name | $acl_entry | \@acl )

This is an alias for L<acl_matches>.

=cut

# ACL检查别名
# 这是acl_matches的别名
sub check_acl_no { goto &acl_matches }

=head2 acl_matches_only( $ip | $object | \%hash | \@item_list, $setting_name | $acl_entry | \@acl )

Given an IP address, object instance, or hash, returns true if the
configuration setting C<$setting_name> matches, else returns false.

Usage of this function is strongly advised to be of the form:

 QUIT/SKIP UNLESS acl_matches_only

The function fails safe, so if the content of the setting or ACL is undefined
or an empty string, then C<acl_matches_only> also returns false.

Further, if the setting or ACL resolves to a list but the list has no items,
then C<acl_matches_only> returns true (as if there is a successful match).

If C<$setting_name> is a valid setting, then it will be resolved to the access
control list, else we assume you passed an ACL entry or ACL.

See L<the Netdisco wiki|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
for details of what C<$acl> may contain.

=cut

# 检查ACL仅匹配
# 给定IP地址、对象实例或哈希，如果配置设置匹配则返回true，否则返回false
sub acl_matches_only {
  my ($thing, $setting_name) = @_;

  # 故障安全，未定义配置应返回false
  return false unless $thing and $setting_name;
  my $config = (exists config->{"$setting_name"} ? setting($setting_name) : $setting_name);

  # 使空配置等同于'any'（即匹配）的逻辑
  # 空列表检查意味着真值检查对匹配或空列表通过
  return true if not $config    # 未定义或空字符串
    or ((ref [] eq ref $config) and not scalar @$config);
  return check_acl($thing, $config);
}

=head2 check_acl_only( $ip | $object | \%hash | \@item_list, $setting_name | $acl_entry | \@acl )

This is an alias for L<acl_matches_only>.

=cut

# ACL仅检查别名
# 这是acl_matches_only的别名
sub check_acl_only { goto &acl_matches_only }

=head2 check_acl( $ip | $object | \%hash | \@item_list, $acl_entry | \@acl )

Given an IP address, object instance, or hash, compares it to the items in
C<< \@acl >> then returns true or false. You can control whether any item must
match or all must match, and items can be negated to invert the match logic.

Also accepts an array reference of multiple IP addresses, object instances,
and hashes, and will test against each in turn, for each ACL rule.

The slots C<alias>, C<ip>, C<switch>, and C<addr> are looked for in the
instance or hash and used to compare a bare IP address (so it works with most
Netdisco database classes, and the L<NetAddr::IP> class). Any instance or hash
slot can be used as an ACL named property.

There are several options for what C<< \@acl >> may contain. See
L<the Netdisco wiki|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
for the details.

=cut

# 检查ACL规则
# 给定IP地址、对象实例或哈希，将其与ACL中的项目进行比较，然后返回true或false
sub check_acl {
  my ($things, $config) = @_;
  return false unless defined $things and defined $config;
  return false if ref [] eq ref $things and not scalar @$things;
  $things = [$things] if ref [] ne ref $things;

  my $real_ip = '';    # 允许为空
                       # 从对象或哈希中提取IP地址
ITEM: foreach my $item (@$things) {
    foreach my $slot (qw/alias ip switch addr/) {
      if (blessed $item) {
        $real_ip = $item->$slot if $item->can($slot) and eval { $item->$slot };
      }
      elsif (ref {} eq ref $item) {
        $real_ip = $item->{$slot} if exists $item->{$slot} and $item->{$slot};
      }
      last ITEM if $real_ip;
    }
  }

  # 如果直接是字符串，则使用它
ITEM: foreach my $item (@$things) {
    last ITEM        if $real_ip;
    $real_ip = $item if (ref $item eq q{}) and $item;
  }

  # 处理配置为单个项目或列表
  $config = [$config] if ref $config eq q{};
  if (ref [] ne ref $config) {
    error "error: acl is not a single item or list (cannot compare to '$real_ip')";
    return false;
  }

  # 检查是否所有规则都必须匹配
  my $all = (scalar grep { $_ eq 'op:and' } @$config);

  # 使用普通IP的常见情况，所以字符串比较以提高速度
  my $find = (scalar grep { not reftype $_ and $_ eq $real_ip } @$config);
  return true if $real_ip and $find and not $all;

  # 创建IP地址对象和DNS解析选项
  my $addr = NetAddr::IP::Lite->new($real_ip);
  my $name = undef;                                                            # 只查找一次，且仅在qr//使用时
  my $ropt = {retry => 1, retrans => 1, udp_timeout => 1, tcp_timeout => 2};
  my $qref = ref qr//;

  # 处理每个ACL规则
RULE: foreach (@$config) {
    my $rule = $_;                                                             # 必须复制以便安全修改
    next RULE if !defined $rule or $rule eq 'op:and';

    # 处理正则表达式规则
    if ($qref eq ref $rule) {

      # 如果没有IP地址，无法匹配其DNS
      next RULE unless $addr;

      $name = ($name || hostname_from_ip($addr->addr, $ropt) || '!!none!!');
      if ($name =~ $rule) {
        return true if not $all;
      }
      else {
        return false if $all;
      }
      next RULE;
    }

    # 检查否定规则
    my $neg = ($rule =~ s/^!//);

    # 处理主机组规则
    if ($rule =~ m/^group:(.+)$/) {
      my $group = $1;
      setting('host_groups')->{$group} ||= [];

      if ($neg xor check_acl($things, setting('host_groups')->{$group})) {
        return true if not $all;
      }
      else {
        return false if $all;
      }
      next RULE;
    }

    if ($rule =~ m/^tag:(.+)$/) {
      my $tag   = $1;
      my $found = false;

    ITEM: foreach my $item (@$things) {
        if (blessed $item and $item->can('tags')) {
          if ($neg xor scalar grep { $_ eq $tag } @{$item->tags || []}) {
            return true if not $all;
            $found = true;
            last ITEM;
          }
        }
        elsif (ref {} eq ref $item and exists $item->{'tags'}) {
          if ($neg xor scalar grep { $_ eq $tag } @{$item->{'tags'} || []}) {
            return true if not $all;
            $found = true;
            last ITEM;
          }
        }
      }

      return false if $all and not $found;
      next RULE;
    }

    # cf:customfield:val
    if ($rule =~ m/^cf:([^:]+):(.*)$/) {
      my $prop  = $1;
      my $match = $2 || '';
      my $found = false;

      # 自定义字段存在，允许undef匹配空字符串
    ITEM: foreach my $item (@$things) {
        my $cf = {};
        if (blessed $item and $item->can('custom_fields')) {
          $cf = from_json($item->custom_fields || '{}');
        }
        elsif (ref {} eq ref $item and exists $item->{'custom_fields'}) {
          $cf = from_json($item->{'custom_fields'} || '{}');
        }

        if (ref {} eq ref $cf and exists $cf->{$prop}) {
          if (
            $neg
            xor (
                   (!defined $cf->{$prop} and $match eq q{})
                or (defined $cf->{$prop} and ref $cf->{$prop} eq q{} and $cf->{$prop} =~ m/^$match$/)
            )
          ) {
            return true if not $all;
            $found = true;
            last ITEM;
          }
        }
      }

      # missing custom field matches empty string
      # #1348 or matches string if $neg is set
      # (which is done in a second pass to allow all @$things to be
      # 检查现有自定义字段）
      if (!$found and ($match eq q{} and not $neg) or (length $match and $neg)) {

      ITEM: foreach my $item (@$things) {
          my $cf = {};
          if (blessed $item and $item->can('custom_fields')) {
            $cf = from_json($item->custom_fields || '{}');
          }
          elsif (ref {} eq ref $item and exists $item->{'custom_fields'}) {
            $cf = from_json($item->{'custom_fields'} || '{}');
          }

          # empty or missing property
          if (ref {} eq ref $cf and !exists $cf->{$prop}) {
            return true if not $all;
            $found = true;
            last ITEM;
          }
        }
      }

      return false if $all and not $found;
      next RULE;
    }

    # prop:val
    # with a check that prop isn't just the first part of a v6 addr
    if ($rule =~ m/^([^:]+):(.*)$/ and $1 !~ m/^[a-f0-9]+$/i) {
      my $prop  = $1;
      my $match = $2 || '';
      my $found = false;

      # 属性存在，允许undef匹配空字符串
    ITEM: foreach my $item (@$things) {
        if (blessed $item and $item->can($prop)) {
          if (
            $neg
            xor (
                   (!defined eval { $item->$prop } and $match eq q{})
                or (defined eval { $item->$prop } and ref $item->$prop eq q{} and $item->$prop =~ m/^$match$/)
            )
          ) {
            return true if not $all;
            $found = true;
            last ITEM;
          }
        }
        elsif (ref {} eq ref $item and exists $item->{$prop}) {
          if (
            $neg
            xor (
                   (!defined $item->{$prop} and $match eq q{})
                or (defined $item->{$prop} and ref $item->{$prop} eq q{} and $item->{$prop} =~ m/^$match$/)
            )
          ) {
            return true if not $all;
            $found = true;
            last ITEM;
          }
        }
      }

      # missing property matches empty string
      # #1348 or matches string if $neg is set
      # (which is done in a second pass to allow all @$things to be
      # 检查现有属性）
      if (!$found and ($match eq q{} and not $neg) or (length $match and $neg)) {

      ITEM: foreach my $item (@$things) {
          if (blessed $item and !$item->can($prop)) {
            return true if not $all;
            $found = true;
            last ITEM;
          }
          elsif (ref {} eq ref $item and !exists $item->{$prop}) {
            return true if not $all;
            $found = true;
            last ITEM;
          }
        }
      }

      return false if $all and not $found;
      next RULE;
    }

    if ($rule =~ m/^\S+\s+\S+\s+\S+\s+\S+\s+\S+/i) {
      my $win_start = time - (time % 60) - 1;
      my $win_end   = $win_start + 60;
      my $cron      = Algorithm::Cron->new(base => 'local', crontab => $rule,) or next RULE;

      if ($neg xor ($cron->next_time($win_start) <= $win_end)) {
        return true if not $all;
      }
      else {
        return false if $all;
      }
      next RULE;
    }

    if ($rule =~ m/[:.]([a-f0-9]+)-([a-f0-9]+)$/i) {
      my $first = $1;
      my $last  = $2;

      # 如果没有IP地址，无法匹配IP范围
      next RULE unless $addr;

      if ($rule =~ m/:/) {
        next RULE if $addr->bits != 128 and not $all;

        $first = hex $first;
        $last  = hex $last;

        (my $header = $rule) =~ s/:[^:]+$/:/;
        foreach my $part ($first .. $last) {
          my $ip = NetAddr::IP::Lite->new($header . sprintf('%x', $part) . '/128') or next;
          if ($neg xor ($ip == $addr)) {
            return true if not $all;
            next RULE;
          }
        }
        return false if (not $neg and $all);
        return true  if ($neg     and not $all);
      }
      else {
        next RULE if $addr->bits != 32 and not $all;

        (my $header = $rule) =~ s/\.[^.]+$/./;
        foreach my $part ($first .. $last) {
          my $ip = NetAddr::IP::Lite->new($header . $part . '/32') or next;
          if ($neg xor ($ip == $addr)) {
            return true if not $all;
            next RULE;
          }
        }
        return false if (not $neg and $all);
        return true  if ($neg     and not $all);
      }
      next RULE;
    }

    # 可能是错误的东西，IP/主机是唯一剩下的选项
    next RULE if ref $rule;

    # 如果没有IP地址，无法匹配IP前缀
    next RULE unless $addr;

    my $ip = NetAddr::IP::Lite->new($rule) or next RULE;
    next RULE if $ip->bits != $addr->bits and not $all;

    if ($neg xor ($ip->contains($addr))) {
      return true if not $all;
    }
    else {
      return false if $all;
    }

    next RULE;
  }

  return ($all ? true : false);
}

true;
