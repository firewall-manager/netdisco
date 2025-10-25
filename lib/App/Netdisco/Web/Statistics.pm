package App::Netdisco::Web::Statistics;

# 统计信息Web模块
# 提供系统统计信息显示功能

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

# 统计信息AJAX路由
# 获取最新的系统统计信息
get '/ajax/content/statistics' => require_login sub {

    # 获取最新的统计信息记录
    my $stats = schema(vars->{'tenant'})->resultset('Statistics')
      ->search(undef, { order_by => { -desc => 'day' }, rows => 1 });

    # 如果存在记录则获取第一条，否则为undef
    $stats = ($stats->count ? $stats->first : undef);

    var( nav => 'statistics' );
    # 渲染统计信息模板
    template 'ajax/statistics.tt',
        { stats => $stats },
        { layout => 'noop' };
};

true;
