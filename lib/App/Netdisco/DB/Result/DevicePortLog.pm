use utf8;
package App::Netdisco::DB::Result::DevicePortLog;

# 设备端口日志结果类
# 提供设备端口操作日志的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device_port_log");
# 定义表列
# 包含日志ID、设备IP、端口、原因、日志内容和用户信息
__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "device_port_log_id_seq",
  },
  "ip",
  { data_type => "inet", is_nullable => 1 },
  "port",
  { data_type => "text", is_nullable => 1 },
  "reason",
  { data_type => "text", is_nullable => 1 },
  "log",
  { data_type => "text", is_nullable => 1 },
  "username",
  { data_type => "text", is_nullable => 1 },
  "userip",
  { data_type => "inet", is_nullable => 1 },
  "action",
  { data_type => "text", is_nullable => 1 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
);

# 设置主键
__PACKAGE__->set_primary_key("id");

=head1 ADDITIONAL COLUMNS

=head2 creation_stamp
 
Formatted version of the C<creation> field, accurate to the second.
 
The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:
 
 2012-02-06 12:49:23
 
=cut
 
# 创建时间戳方法
# 返回creation字段的格式化版本，精确到秒
sub creation_stamp  { return (shift)->get_column('creation_stamp')  }

1;
