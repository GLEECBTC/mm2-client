package mm2_tools_server

import (
	"github.com/fasthttp/router"
)


func InitRooter(onlyPriceService bool) *router.Router {
	r := router.New()

	if !onlyPriceService {
		r.POST("/api/v1/start_price_service", StartPriceService)
	}

	r.POST("/api/v1/ticker_infos", TickerInfos)
	r.GET("/api/v1/tickers", TickerAllInfos)
	r.GET("/api/v2/tickers", TickerAllInfosV2)
	r.GET("/api/v1/ping", Ping)
	r.POST("/api/v1/cex_rates", CexRates)
	r.POST("/api/v1/volume24h", Volume24h)
	return r
}
