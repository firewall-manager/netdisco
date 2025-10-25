package App::Netdisco::GenericDB::Result::Virtual::GenericReport;

# 通用报告虚拟结果集模块
# 提供通用报告功能的虚拟数据库视图

use strict;
use warnings;

use base 'DBIx::Class::Core';

# 设置表类为视图
__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

# 设置表名为generic_report
__PACKAGE__->table("generic_report");

# 标记为虚拟结果集
__PACKAGE__->result_source_instance->is_virtual(1);

# 设置视图定义（当前为空）
__PACKAGE__->result_source_instance->view_definition(q{});

1;
