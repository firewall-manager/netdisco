package App::Netdisco::DB::ResultSet::Subnet;

# 子网结果集类
# 提供子网相关的数据库查询功能

use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(
  qw/
    +App::Netdisco::DB::ExplicitLocking
    /
);

1;
