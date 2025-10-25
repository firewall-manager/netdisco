package App::Netdisco::DB::ResultSet::DeviceSkip;

# 设备跳过结果集类
# 提供设备跳过相关的数据库查询功能

use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

1;
