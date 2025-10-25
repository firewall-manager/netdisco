use utf8;
package App::Netdisco::DB::Result::UserLog;

# 用户日志结果类
# 提供用户操作日志信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("user_log");
# 定义表列
# 包含日志条目、用户名、IP地址、事件、详情和创建时间
__PACKAGE__->add_columns(
  "entry",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "user_log_entry_seq",
  },
  "username",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "userip",
  { data_type => "inet", is_nullable => 1 },
  "event",
  { data_type => "text", is_nullable => 1 },
  "details",
  { data_type => "text", is_nullable => 1 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
);

1;
