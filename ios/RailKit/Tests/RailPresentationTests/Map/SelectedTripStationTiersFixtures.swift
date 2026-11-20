/// Real station sequences of three sample trips (`app/data/sample-data/sample-full.json`),
/// with coordinates from `app/data/registry-bundle/jp.json` (station code -> station -> complex lat/lon). Generated; do not edit by hand.
enum SelectedTripStationTiersFixtures {
    struct Stop {
        let name: String
        let stopType: String
        let lat: Double
        let lon: Double
    }

    /// 丸ノ内線 大手町→池袋, 普通.
    static let marunouchi: [Stop] = [
        Stop(name: "大手町", stopType: "origin", lat: 35.68553, lon: 139.76461),
        Stop(name: "淡路町", stopType: "passenger_stop", lat: 35.69487, lon: 139.76746),
        Stop(name: "御茶ノ水", stopType: "passenger_stop", lat: 35.69988, lon: 139.76482),
        Stop(name: "本郷三丁目", stopType: "passenger_stop", lat: 35.70716, lon: 139.76039),
        Stop(name: "後楽園", stopType: "passenger_stop", lat: 35.70785, lon: 139.75132),
        Stop(name: "茗荷谷", stopType: "passenger_stop", lat: 35.71720, lon: 139.73690),
        Stop(name: "新大塚", stopType: "passenger_stop", lat: 35.72613, lon: 139.72935),
        Stop(name: "池袋", stopType: "destination", lat: 35.72981, lon: 139.71108),
    ]

    /// 湘南新宿ライン 特別快速 大宮→横浜.
    static let shonanShinjuku: [Stop] = [
        Stop(name: "大宮", stopType: "origin", lat: 35.90664, lon: 139.62340),
        Stop(name: "さいたま新都心", stopType: "pass_through", lat: 35.89359, lon: 139.63390),
        Stop(name: "与野", stopType: "pass_through", lat: 35.88437, lon: 139.63899),
        Stop(name: "北浦和", stopType: "pass_through", lat: 35.87220, lon: 139.64575),
        Stop(name: "浦和", stopType: "passenger_stop", lat: 35.85856, lon: 139.65715),
        Stop(name: "南浦和", stopType: "pass_through", lat: 35.84796, lon: 139.66878),
        Stop(name: "蕨", stopType: "pass_through", lat: 35.82793, lon: 139.69042),
        Stop(name: "西川口", stopType: "pass_through", lat: 35.81551, lon: 139.70436),
        Stop(name: "川口", stopType: "pass_through", lat: 35.80182, lon: 139.71750),
        Stop(name: "赤羽", stopType: "passenger_stop", lat: 35.77772, lon: 139.72085),
        Stop(name: "十条", stopType: "pass_through", lat: 35.76039, lon: 139.72225),
        Stop(name: "板橋", stopType: "pass_through", lat: 35.74499, lon: 139.71917),
        Stop(name: "池袋", stopType: "passenger_stop", lat: 35.72981, lon: 139.71108),
        Stop(name: "目白", stopType: "pass_through", lat: 35.72039, lon: 139.70628),
        Stop(name: "高田馬場", stopType: "pass_through", lat: 35.71288, lon: 139.70428),
        Stop(name: "新大久保", stopType: "pass_through", lat: 35.70093, lon: 139.70025),
        Stop(name: "新宿", stopType: "passenger_stop", lat: 35.68988, lon: 139.69968),
        Stop(name: "代々木", stopType: "pass_through", lat: 35.68380, lon: 139.70206),
        Stop(name: "原宿", stopType: "pass_through", lat: 35.67131, lon: 139.70269),
        Stop(name: "渋谷", stopType: "passenger_stop", lat: 35.65897, lon: 139.70160),
        Stop(name: "恵比寿", stopType: "pass_through", lat: 35.64685, lon: 139.70943),
        Stop(name: "目黒", stopType: "pass_through", lat: 35.63259, lon: 139.71570),
        Stop(name: "五反田", stopType: "pass_through", lat: 35.62613, lon: 139.72392),
        Stop(name: "大崎", stopType: "passenger_stop", lat: 35.61982, lon: 139.72799),
        Stop(name: "西大井", stopType: "pass_through", lat: 35.60170, lon: 139.72160),
        Stop(name: "武蔵小杉", stopType: "passenger_stop", lat: 35.57467, lon: 139.66336),
        Stop(name: "新川崎", stopType: "pass_through", lat: 35.55173, lon: 139.67155),
        Stop(name: "鶴見", stopType: "pass_through", lat: 35.50831, lon: 139.67609),
        Stop(name: "新子安", stopType: "pass_through", lat: 35.48678, lon: 139.65405),
        Stop(name: "東神奈川", stopType: "pass_through", lat: 35.47793, lon: 139.63308),
        Stop(name: "横浜", stopType: "destination", lat: 35.46580, lon: 139.62189),
    ]

    /// はやぶさ27号 東京→新函館北斗.
    static let hayabusa: [Stop] = [
        Stop(name: "東京", stopType: "origin", lat: 35.68141, lon: 139.76652),
        Stop(name: "上野", stopType: "passenger_stop", lat: 35.71249, lon: 139.77646),
        Stop(name: "大宮", stopType: "passenger_stop", lat: 35.90664, lon: 139.62340),
        Stop(name: "小山", stopType: "pass_through", lat: 36.31286, lon: 139.80645),
        Stop(name: "宇都宮", stopType: "pass_through", lat: 36.55942, lon: 139.89852),
        Stop(name: "那須塩原", stopType: "pass_through", lat: 36.93162, lon: 140.02087),
        Stop(name: "新白河", stopType: "pass_through", lat: 37.12292, lon: 140.18818),
        Stop(name: "郡山", stopType: "pass_through", lat: 37.39826, lon: 140.38880),
        Stop(name: "福島", stopType: "pass_through", lat: 37.75451, lon: 140.45963),
        Stop(name: "白石蔵王", stopType: "pass_through", lat: 37.99477, lon: 140.63279),
        Stop(name: "仙台", stopType: "passenger_stop", lat: 38.25995, lon: 140.88189),
        Stop(name: "古川", stopType: "pass_through", lat: 38.57076, lon: 140.96782),
        Stop(name: "くりこま高原", stopType: "pass_through", lat: 38.74885, lon: 141.07157),
        Stop(name: "一ノ関", stopType: "pass_through", lat: 38.92656, lon: 141.13846),
        Stop(name: "水沢江刺", stopType: "pass_through", lat: 39.14516, lon: 141.18870),
        Stop(name: "北上", stopType: "pass_through", lat: 39.28168, lon: 141.12179),
        Stop(name: "新花巻", stopType: "pass_through", lat: 39.40615, lon: 141.17332),
        Stop(name: "盛岡", stopType: "passenger_stop", lat: 39.70134, lon: 141.13644),
        Stop(name: "いわて沼宮内", stopType: "pass_through", lat: 39.96060, lon: 141.21725),
        Stop(name: "二戸", stopType: "pass_through", lat: 40.25980, lon: 141.28579),
        Stop(name: "八戸", stopType: "passenger_stop", lat: 40.50923, lon: 141.43125),
        Stop(name: "七戸十和田", stopType: "pass_through", lat: 40.71993, lon: 141.15391),
        Stop(name: "新青森", stopType: "passenger_stop", lat: 40.82792, lon: 140.69343),
        Stop(name: "奥津軽いまべつ", stopType: "pass_through", lat: 41.14485, lon: 140.51570),
        Stop(name: "木古内", stopType: "pass_through", lat: 41.67804, lon: 140.43403),
        Stop(name: "新函館北斗", stopType: "destination", lat: 41.90472, lon: 140.64880),
    ]
}
