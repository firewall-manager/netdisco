use utf8;
package App::Netdisco::GenericDB;

use strict;
use warnings;

# 通用数据库模式基类
# 用于处理外部数据库连接，不包含Netdisco特定的表结构
use base 'DBIx::Class::Schema';
# 加载所有命名空间（表类和结果集类）
__PACKAGE__->load_namespaces();

1;
