# Netdisco VLAN搜索插件
# 此模块提供VLAN搜索功能，支持VLAN名称和编号搜索
package App::Netdisco::Web::Plugin::Search::VLAN;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册搜索标签页 - VLAN搜索，支持CSV导出和API接口
register_search_tab({
    tag => 'vlan',
    label => 'VLAN',
    provides_csv => 1,
    api_endpoint => 1,
    api_parameters => [
      q => {
        description => 'VLAN name or number',
        required => 1,
      },
    ],
});

# VLAN搜索路由 - 查找携带指定VLAN的设备
get '/ajax/content/search/vlan' => require_login sub {
    # 获取查询参数
    my $q = param('q');
    send_error( 'Missing query', 400 ) unless $q;
    return unless ($q =~ m/\w/); # 需要至少一些字母数字字符
    my $rs;

    # 根据查询类型选择搜索方法
    if ( $q =~ m/^\d+$/ ) {
        # 数字查询：按VLAN编号搜索
        $rs = schema(vars->{'tenant'})->resultset('Device')
            ->carrying_vlan( { vlan => $q } );
    }
    else {
        # 文本查询：按VLAN名称搜索
        $rs = schema(vars->{'tenant'})->resultset('Device')
            ->carrying_vlan_name( { name => $q } );
    }

    # 获取搜索结果
    my @results = $rs->hri->all;
    return unless scalar @results;

    # 根据请求类型返回不同格式的数据
    if (request->is_ajax) {
        # AJAX请求：返回JSON格式的HTML模板
        my $json = to_json( \@results );
        template 'ajax/search/vlan.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        # 非AJAX请求：返回CSV格式数据
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/search/vlan_csv.tt', { results => \@results }, { layout => 'noop' };
    }
};

1;
