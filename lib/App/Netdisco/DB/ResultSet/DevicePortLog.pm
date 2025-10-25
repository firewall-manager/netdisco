package App::Netdisco::DB::ResultSet::DevicePortLog;

# 设备端口日志结果集类
# 提供设备端口日志相关的数据库查询功能

use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=head2 with_times

This is a modifier for any C<search()> which will add the following additional
synthesized column to the result set:

=over 4

=item creation_stamp

=back

=cut

# 带时间戳
# 为任何search()添加时间相关的合成列
sub with_times {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+columns' => {
          creation_stamp => \"to_char(creation, 'YYYY-MM-DD HH24:MI:SS')",
        },
      });
}

1;
