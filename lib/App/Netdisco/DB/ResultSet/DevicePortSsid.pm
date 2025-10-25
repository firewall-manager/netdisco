package App::Netdisco::DB::ResultSet::DevicePortSsid;

# 设备端口SSID结果集类
# 提供设备端口SSID相关的数据库查询功能

use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(
  qw/
    +App::Netdisco::DB::ExplicitLocking
    /
);

=head1 ADDITIONAL METHODS

=head2 get_ssids

Returns a sorted list of SSIDs with the following columns only:

=over 4

=item ssid

=item broadcast

=item count

=back

Where C<count> is the number of instances of the SSID in the Netdisco
database.

=cut

# 获取SSID列表
# 返回SSID的排序列表，包括ssid、broadcast、count列
sub get_ssids {
  my $rs = shift;

  return $rs->search(
    {},
    {
      select   => ['ssid', 'broadcast', {count => 'ssid'}],
      as       => [qw/ ssid broadcast count /],
      group_by => [qw/ ssid broadcast /],
      order_by => {-desc => [qw/count/]},
    }
  );

}

1;
