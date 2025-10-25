use utf8;
package App::Netdisco::DB::Result::Statistics;

# 统计结果类
# 提供系统统计信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("statistics");
# 定义表列
# 包含日期、设备统计、端口统计、节点统计、电话统计、无线统计和版本信息
__PACKAGE__->add_columns(
  "day",
  { data_type => "date", default_value => \"CURRENT_DATE", is_nullable => 0 },
  "device_count",
  { data_type => "integer", is_nullable => 0 },
  "device_ip_count",
  { data_type => "integer", is_nullable => 0 },
  "device_link_count",
  { data_type => "integer", is_nullable => 0 },
  "device_port_count",
  { data_type => "integer", is_nullable => 0 },
  "device_port_up_count",
  { data_type => "integer", is_nullable => 0 },
  "ip_table_count",
  { data_type => "integer", is_nullable => 0 },
  "ip_active_count",
  { data_type => "integer", is_nullable => 0 },
  "node_table_count",
  { data_type => "integer", is_nullable => 0 },
  "node_active_count",
  { data_type => "integer", is_nullable => 0 },
  "phone_count",
  { data_type => "integer", is_nullable => 0 },
  "wap_count",
  { data_type => "integer", is_nullable => 0 },
  "netdisco_ver",
  { data_type => "text", is_nullable => 1 },
  "snmpinfo_ver",
  { data_type => "text", is_nullable => 1 },
  "schema_ver",
  { data_type => "text", is_nullable => 1 },
  "perl_ver",
  { data_type => "text", is_nullable => 1 },
  "python_ver",
  { data_type => "text", is_nullable => 1 },
  "pg_ver",
  { data_type => "text", is_nullable => 1 },
);

# 设置主键
__PACKAGE__->set_primary_key("day");

1;
