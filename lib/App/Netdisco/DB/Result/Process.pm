use utf8;
package App::Netdisco::DB::Result::Process;

# 进程结果类
# 提供系统进程信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("process");
# 定义表列
# 包含控制器、设备、动作、状态、计数和创建时间信息
__PACKAGE__->add_columns(
  "controller",
  { data_type => "integer", is_nullable => 0 },
  "device",
  { data_type => "inet", is_nullable => 0 },
  "action",
  { data_type => "text", is_nullable => 0 },
  "status",
  { data_type => "text", is_nullable => 1 },
  "count",
  { data_type => "integer", is_nullable => 1 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
);


1;
