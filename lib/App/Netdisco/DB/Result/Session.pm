use utf8;
package App::Netdisco::DB::Result::Session;

# 会话结果类
# 提供用户会话信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("sessions");
# 定义表列
# 包含会话ID、创建时间和会话数据
__PACKAGE__->add_columns(
  "id",
  { data_type => "char", is_nullable => 0, size => 32 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "a_session",
  { data_type => "text", is_nullable => 1 },
);

# 设置主键
__PACKAGE__->set_primary_key("id");

1;
