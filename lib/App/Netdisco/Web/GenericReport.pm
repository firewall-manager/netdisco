package App::Netdisco::Web::GenericReport;

# 通用报告Web模块
# 提供自定义报告生成功能

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use Path::Class 'file';
use Storable 'dclone';
use Safe;

use HTML::Entities 'encode_entities';
use Regexp::Common            qw( RE_net_IPv4 RE_net_IPv6 RE_net_MAC RE_net_domain );
use Regexp::Common::net::CIDR ();

our ($config, @data);

# 注册自定义报告
foreach my $report (@{setting('reports')}) {
  my $r = $report->{tag};

  register_report({
    tag      => $r,
    label    => $report->{label},
    category => ($report->{category} || 'My Reports'),
    ($report->{hidden} ? (hidden => true) : ()),
    provides_csv   => true,
    api_endpoint   => true,
    bind_params    => [map { ref $_ ? $_->{param} : $_ } @{$report->{bind_params}}],
    api_parameters => $report->{api_parameters},
  });

  # 报告内容路由
  get "/ajax/content/report/$r" => require_login sub {

    # TODO: 这应该通过动态创建新的Virtual Result类来完成
    # (package...) 然后调用DBIC register_class

    my $schema = ($report->{database} || vars->{'tenant'});
    my $rs     = schema($schema)->resultset('Virtual::GenericReport')->result_source;
    (my $query = $report->{query}) =~ s/;$//;

    # 解析相当复杂的'columns'配置以获取字段、
    # 显示名称和"_"前缀选项
    my %column_config = ();
    my @column_order  = ();
    foreach my $col (@{$report->{columns}}) {
      foreach my $k (keys %$col) {
        if ($k !~ m/^_/) {
          push @column_order, $k;
          $column_config{$k} = dclone($col || {});
          $column_config{$k}->{displayname} = delete $column_config{$k}->{$k};
        }
      }
    }

    $rs->view_definition($query);
    $rs->remove_columns($rs->columns);
    $rs->add_columns(exists $report->{query_columns} ? @{$report->{query_columns}} : @column_order);

    # 执行查询
    my $set = schema($schema)->resultset('Virtual::GenericReport')->search(
      undef, {
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        (
            (exists $report->{bind_params})
          ? (bind => [map { param($_) } map { ref $_ ? $_->{param} : $_ } @{$report->{bind_params}}])
          : ()
        ),
      }
    );
    @data = $set->all;

    # 数据整理支持...

    my $compartment = Safe->new;
    $config = $report;    # 此报告的配置闭包
    $compartment->share(qw/$config @data/);
    $compartment->permit_only(qw/:default sort/);

    # 执行数据整理脚本
    my $munger  = file(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'site_plugins', $r)->stringify;
    my @results = ((-f $munger) ? $compartment->rdo($munger) : @data);
    return if $@ or (0 == scalar @results);

    if (request->is_ajax) {

      # 可搜索字段支持...

      my $recidr4 = $RE{net}{CIDR}{IPv4}{-keep};    #RE_net_CIDR_IPv4(-keep);
      my $rev4    = RE_net_IPv4(-keep);
      my $rev6    = RE_net_IPv6(-keep);
      my $remac   = RE_net_MAC(-keep);

      # 处理搜索结果链接
      foreach my $row (@results) {
        foreach my $col (@column_order) {
          next unless $column_config{$col}->{_searchable};
          my $fields = (ref $row->{$col} ? $row->{$col} : [$row->{$col}]);

          foreach my $f (@$fields) {

            encode_entities($f);

            # 处理CIDR链接
            $f =~ s!\b${recidr4}\b!'<a href="'.
                        uri_for('/search', {q => "$1/$2"})->path_query
                        .qq{">$1/$2</a>}!gex;

            if (not $1 and not $2) {

              # 处理IPv4链接
              $f =~ s!\b${rev4}\b!'<a href="'.
                            uri_for('/search', {q => $1})->path_query .qq{">$1</a>}!gex;
            }

            # 处理IPv6链接
            $f =~ s!\b${rev6}\b!'<a href="'.
                        uri_for('/search', {q => $1})->path_query .qq{">$1</a>}!gex;

            # 处理MAC地址链接
            $f =~ s!\b${remac}\b!'<a href="'.
                        uri_for('/search', {q => $1})->path_query .qq{">$1</a>}!gex;

            $row->{$col} = $f if not ref $row->{$col};
          }
        }
      }

      # 渲染HTML模板
      template 'ajax/report/generic_report.tt', {
        results          => \@results,
        is_custom_report => true,
        column_options   => \%column_config,
        headings         => [map { $column_config{$_}->{displayname} } @column_order],
        columns          => [@column_order]
        },
        {layout => 'noop'};
    }
    else {
      # 渲染CSV模板
      header('Content-Type' => 'text/comma-separated-values');
      template 'ajax/report/generic_report_csv.tt', {
        results  => \@results,
        headings => [map { $column_config{$_}->{displayname} } @column_order],
        columns  => [@column_order]
        },
        {layout => 'noop'};
    }
  };
}

true;
