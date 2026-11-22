import Foundation

/// Fallback dish photos when UMass Dining doesn't publish item images.
/// Match the **dish name first** (most specific), then station — never let a station
/// like "Desserts" or "Noodle Bowl" override a clear dish keyword.
enum FoodImageCatalog {
    private static let dishRules: [(keys: [String], url: String)] = [
        (["ramen", "shoyu", "udon", "pho"], "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=600&auto=format&fit=crop"),
        (["pizza"], "https://images.unsplash.com/photo-1513104890138-7c749659a591?w=600&auto=format&fit=crop"),
        (["burger", "smash"], "https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=600&auto=format&fit=crop"),
        (["sushi", "nigiri", "maki", "sashimi"], "https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=600&auto=format&fit=crop"),
        (["soup", "chowder", "bisque", "broth"], "https://images.unsplash.com/photo-1547592166-23ac45744acd?w=600&auto=format&fit=crop"),
        (["salad", "greens", "arugula", "caesar"], "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=600&auto=format&fit=crop"),
        (["spaghetti", "lasagna", "penne", "fettuccine", "macaroni", "pasta"], "https://images.unsplash.com/photo-1621996346565-e3dbc646d9a9?w=600&auto=format&fit=crop"),
        (["lo mein", "chow mein", "stir fry"], "https://images.unsplash.com/photo-1585032226651-759b368d7246?w=600&auto=format&fit=crop"),
        (["taco", "burrito", "quesadilla", "tamale", "nacho"], "https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=600&auto=format&fit=crop"),
        (["wing", "tenders", "nugget"], "https://images.unsplash.com/photo-1527477396000-e27173b8ed81?w=600&auto=format&fit=crop"),
        (["chicken"], "https://images.unsplash.com/photo-1598103442097-8b74394b95c6?w=600&auto=format&fit=crop"),
        (["steak", "brisket", "beef"], "https://images.unsplash.com/photo-1600891964092-4316c288032e?w=600&auto=format&fit=crop"),
        (["salmon", "tuna", "cod", "fish"], "https://images.unsplash.com/photo-1519708227418-c8fd9a32b7a2?w=600&auto=format&fit=crop"),
        (["french toast", "pancake", "waffle", "omelet", "egg", "biscuit", "breakfast"], "https://images.unsplash.com/photo-1525351484163-7529414344d8?w=600&auto=format&fit=crop"),
        (["coffee", "latte", "espresso", "cappuccino"], "https://images.unsplash.com/photo-1461023058943-07fcbe16d735?w=600&auto=format&fit=crop"),
        (["oat bar", "granola", "cookie", "brownie", "blondie"], "https://images.unsplash.com/photo-1499636136210-6f4ee915583e?w=600&auto=format&fit=crop"),
        (["cake", "pie", "cheesecake"], "https://images.unsplash.com/photo-1578985545062-69928b1d9587?w=600&auto=format&fit=crop"),
        (["donut", "doughnut", "beignet"], "https://images.unsplash.com/photo-1551024601-bec78aea704b?w=600&auto=format&fit=crop"),
        (["sandwich", "panini", "wrap", "bagel", "club"], "https://images.unsplash.com/photo-1528735602780-2552fd8c2fcb?w=600&auto=format&fit=crop"),
        (["fries", "potato", "hash"], "https://images.unsplash.com/photo-1573080496689-91bc8691f4c4?w=600&auto=format&fit=crop"),
        (["rice bowl", "grain bowl", "power bowl"], "https://images.unsplash.com/photo-1512058564366-18510be2db19?w=600&auto=format&fit=crop"),
    ]

    private static let stationRules: [(keys: [String], url: String)] = [
        (["grill"], "https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=600&auto=format&fit=crop"),
        (["dessert", "bakery", "pastry"], "https://images.unsplash.com/photo-1499636136210-6f4ee915583e?w=600&auto=format&fit=crop"),
        (["noodle", "ramen"], "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=600&auto=format&fit=crop"),
        (["pizza"], "https://images.unsplash.com/photo-1513104890138-7c749659a591?w=600&auto=format&fit=crop"),
        (["salad"], "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=600&auto=format&fit=crop"),
        (["soup"], "https://images.unsplash.com/photo-1547592166-23ac45744acd?w=600&auto=format&fit=crop"),
        (["deli", "sandwich"], "https://images.unsplash.com/photo-1528735602780-2552fd8c2fcb?w=600&auto=format&fit=crop"),
    ]

    private static let fallback =
        "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=600&auto=format&fit=crop"

    static func url(forDishName name: String, station: String = "") -> URL? {
        let dish = name.lowercased()
        let stationHay = station.lowercased()
        for rule in dishRules where rule.keys.contains(where: { dish.contains($0) }) {
            return URL(string: rule.url)
        }
        for rule in stationRules where rule.keys.contains(where: { stationHay.contains($0) }) {
            return URL(string: rule.url)
        }
        return URL(string: fallback)
    }

    /// Prefer a freshly matched photo over a stale/wrong stored URL.
    static func resolving(_ existing: URL?, dishName: String, station: String = "") -> URL? {
        url(forDishName: dishName, station: station) ?? existing
    }
}
