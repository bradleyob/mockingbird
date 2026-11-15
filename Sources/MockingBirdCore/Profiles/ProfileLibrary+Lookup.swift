extension ProfileLibrary {
    /// Profiles of the given category, in library order.
    public func profiles(for category: ScaleCategory) -> [ScaleProfile] {
        profiles.filter { $0.category == category }
    }

    /// Profiles rooted on the given pitch class, in library order.
    public func profiles(for root: PitchClass) -> [ScaleProfile] {
        profiles.filter { $0.root == root }
    }
}
