use utf8;
package App::Netdisco::DB;

use strict;
use warnings;

use base 'DBIx::Class::Schema';

# 加载命名空间，设置默认结果集类
__PACKAGE__->load_namespaces(default_resultset_class => 'ResultSet',);

our                 # 尝试从kwalitee隐藏
  $VERSION = 95;    # 用于升级的模式版本，保持为整数

use Path::Class;
use File::ShareDir 'dist_dir';

# 设置模式版本目录路径
our $schema_versions_dir = Path::Class::Dir->new(dist_dir('App-Netdisco'))->subdir('schema_versions')->stringify;

# 加载自定义组件
__PACKAGE__->load_components(
  qw/
    +App::Netdisco::DB::SchemaVersioned
    +App::Netdisco::DB::ExplicitLocking
    /
);

# 设置升级目录
__PACKAGE__->upgrade_directory($schema_versions_dir);

1;
