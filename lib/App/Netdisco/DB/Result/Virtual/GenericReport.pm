package App::Netdisco::DB::Result::Virtual::GenericReport;

# 通用报告虚拟结果类
# 提供通用报告功能的虚拟视图，支持动态查询

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table("generic_report");
__PACKAGE__->result_source_instance->is_virtual(1);

# 虚拟视图定义：通用报告
# 空视图定义，支持动态查询构建
__PACKAGE__->result_source_instance->view_definition(q{});

1;
