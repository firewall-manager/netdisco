package App::Netdisco::DB::ResultSet;

# 数据库结果集基类
# 提供DataTables支持和集合操作功能

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::SetOperations
  Helper::ResultSet::Shortcut
  Helper::ResultSet::CorrelateRelationship
/);

=head1 ADDITIONAL METHODS

=head2 get_distinct_col( $column )

Returns an asciibetical sorted list of the distinct values in the given column
of the Device table. This is useful for web forms when you want to provide a
drop-down list of possible options.

=cut

# 获取唯一列值
# 返回给定列的不同值的字母排序列表
sub get_distinct_col {
    my ( $rs, $col ) = @_;
    return $rs unless $col;

    return $rs->search(
        {},
        {   columns  => [$col],
            order_by => $col,
            distinct => 1
        }
    )->get_column($col)->all;
}

=head2 get_datatables_data( $params )

Returns a ResultSet for DataTables Server-side processing which populates
the displayed table.  Evaluates the supplied query parameters for filtering,
paging, and ordering information.  Note: query parameters are expected to be
passed as a reference to an expanded hash of hashes.

Filtering if present, will generate simple LIKE matching conditions for each
searchable column (searchability indicated by query parameters) after each
column is casted to text.  Conditions are combined as disjunction (OR).
Note: this does not match the built-in DataTables filtering which does it
word by word on any field. 

=cut

# 获取DataTables数据
# 返回用于DataTables服务器端处理的结果集
sub get_datatables_data {
    my $rs     = shift;
    my $params = shift;
    my $attrs  = shift;

    die "condition parameter to search_by_field must be hashref\n"
        if ref {} ne ref $params
            or 0 == scalar keys %$params;

    # -- 分页
    $rs = $rs->_with_datatables_paging($params);

    # -- 排序
    $rs = $rs->_with_datatables_order_clause($params);

    # -- 过滤
    $rs = $rs->_with_datatables_where_clause($params);

    return $rs;
}

=head2 get_datatables_filtered_count( $params )

Returns the total records, after filtering (i.e. the total number of
records after filtering has been applied - not just the number of records
being returned for this page of data) for a datatables ResultSet and
query parameters.  Note: query parameters are expected to be passed as a
reference to an expanded hash of hashes.

=cut

# 获取DataTables过滤计数
# 返回过滤后的总记录数
sub get_datatables_filtered_count {
    my $rs     = shift;
    my $params = shift;

    return $rs->_with_datatables_where_clause($params)->count;

}

# DataTables排序子句
# 处理DataTables的排序参数
sub _with_datatables_order_clause {
    my $rs     = shift;
    my $params = shift;
    my $attrs  = shift;

    my @order = ();

    if ( defined $params->{'order'}{0} ) {
        for ( my $i = 0; $i < (scalar keys %{$params->{'order'}}); $i++ ) {

           # 构建方向，必须是'-asc'或'-desc'（参考SQL::Abstract）
           # 我们只得到'asc'或'desc'，所以必须用'-'前缀
            my $direction = '-' . $params->{'order'}{$i}{'dir'};

            # 我们只得到列索引（从0开始），所以必须
            # 将索引转换为列名
            my $column_name = _datatables_index_to_column( $params,
                $params->{'order'}{$i}{'column'} );

            # 如果没有前缀，则添加表别名前缀
            my $csa = $rs->current_source_alias;
            $column_name =~ s/^(\w+)$/$csa\.$1/x;
            push @order, { $direction => $column_name };
        }
    }

    $rs = $rs->order_by( \@order );
    return $rs;
}

# 注意：这与内置的DataTables过滤不匹配，后者是逐字段逐词进行的
#
# 使用LIKE的通用过滤，这不会高效，因为无法使用索引

# DataTables WHERE子句
# 处理DataTables的过滤参数
sub _with_datatables_where_clause {
    my $rs     = shift;
    my $params = shift;
    my $attrs  = shift;

    my %where = ();

    if ( defined $params->{'search'}{'value'}
        && $params->{'search'}{'value'} )
    {
        my $search_string = $params->{'search'}{'value'};
        for ( my $i = 0; $i < (scalar keys %{$params->{'columns'}}); $i++ ) {

           # 遍历每个列并检查是否可搜索
           # 如果是，则向where子句添加约束限制给定列
           # 在查询中，列由其索引标识，我们需要将索引转换为列名
            if (    $params->{'columns'}{$i}{'searchable'}
                and $params->{'columns'}{$i}{'searchable'} eq 'true' )
            {
                my $column = _datatables_index_to_column( $params, $i );
                my $csa = $rs->current_source_alias;
                $column =~ s/^(\w+)$/$csa\.$1/x;

                # 将所有内容转换为文本以进行LIKE搜索
                $column = $column . '::text';
                push @{ $where{'-or'} },
                    { $column => { -like => '%' . $search_string . '%' } };
            }
        }
    }

    $rs = $rs->search( \%where, $attrs );
    return $rs;
}

# DataTables分页
# 处理DataTables的分页参数
sub _with_datatables_paging {
    my $rs     = shift;
    my $params = shift;
    my $attrs  = shift;

    my $limit = $params->{'length'};

    my $offset = 0;
    if ( defined $params->{'start'} && $params->{'start'} ) {
        $offset = $params->{'start'};
    }
    $attrs->{'offset'} = $offset;

    $rs = $rs->search( {}, $attrs );
    $rs = $rs->limit($limit) if ($limit and $limit > 0);

    return $rs;
}

# 使用DataTables columns.data定义从索引派生列名

# DataTables索引到列名转换
# 将DataTables列索引转换为实际的列名
sub _datatables_index_to_column {
    my $params = shift;
    my $i      = shift;

    my $field;

    if ( !defined($i) ) {
        $i = 0;
    }
    $field = $params->{'columns'}{$i}{'data'};
    return $field;
}

1;
