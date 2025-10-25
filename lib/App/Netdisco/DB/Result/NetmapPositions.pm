use utf8;
package App::Netdisco::DB::Result::NetmapPositions;

# 网络地图位置结果类
# 提供网络地图设备位置信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("netmap_positions");

# 定义表列
# 包含地图位置ID、设备、主机组、位置、VLAN、深度和位置信息
__PACKAGE__->add_columns(
  "id",          {data_type => "integer", is_nullable => 0, is_auto_increment => 1},
  "device",      {data_type => "inet",    is_nullable => 1},
  "host_groups", {data_type => "text[]",  is_nullable => 0},
  "locations",   {data_type => "text[]",  is_nullable => 0},
  "vlan",        {data_type => "integer", is_nullable => 0, default => 0},
  "depth",       {data_type => "integer", is_nullable => 0, default => 0},
  "positions",   {data_type => "text",    is_nullable => 0},
);

# 设置主键
__PACKAGE__->set_primary_key("id");

1;
