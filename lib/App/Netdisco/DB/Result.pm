package App::Netdisco::DB::Result;

# 数据库结果基类
# 提供JSON序列化和数据类型的支持

use strict;
use warnings;

use base 'DBIx::Class::Core';

BEGIN {
  no warnings 'redefine';
  __PACKAGE__->load_components(qw{Helper::Row::ToJSON});

  # 此替换将避免关系名称覆盖字段名称的问题
  # 导致TO_JSON返回对象实例，破坏to_json
  *DBIx::Class::Helper::Row::ToJSON::TO_JSON = sub {
      my $self = shift;
      my $columns_info = $self->columns_info($self->serializable_columns);
      my $columns_data = { $self->get_columns };
      return {
         map +($_ => $columns_data->{$_}), keys %$columns_info
      };
  };
}

# 用于DBIx::Class::Helper::Row::ToJSON
# 允许文本列包含在结果中

# 不可序列化的数据类型
# 定义不能进行JSON序列化的数据类型
sub unserializable_data_types {
   return {
      blob  => 1,
      ntext => 1,
   };
}

1;
