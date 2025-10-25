package App::Netdisco::DB::ResultSet::DeviceBrowser;

# 设备浏览器结果集类
# 提供设备浏览器相关的数据库查询功能

use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

=head1 ADDITIONAL METHODS

=head2 with_snmp_object( $ip )

Returns a correlated subquery for the set of C<snmp_object> entry for 
the walked data row.

=cut

# 带SNMP对象
# 返回用于遍历数据行的snmp_object条目集合的相关子查询
sub with_snmp_object {
  my ($rs, $ip) = @_;
  $ip ||= '255.255.255.255';

  return $rs->search(undef,{
    # 注意：绑定参数列表顺序很重要
    join => ['snmp_object'],
    bind => [$ip],
    prefetch => 'snmp_object',
  });
}

1;
