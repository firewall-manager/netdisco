package App::Netdisco::DB::SchemaVersioned;

# 版本化数据库模式组件
# 提供数据库模式版本管理和SQL语句执行功能

use strict;
use warnings;

use base 'DBIx::Class::Schema::Versioned';

use Try::Tiny;
use DBIx::Class::Carp;

# 应用SQL语句
# 在事务中安全执行SQL语句，支持错误处理和调试跟踪
sub apply_statement {
    my ($self, $statement) = @_;
    try { $self->storage->txn_do(sub { $self->storage->dbh->do($statement) }) }
    catch { carp "SQL was: $statement" if $ENV{DBIC_TRACE} };
}

1;
