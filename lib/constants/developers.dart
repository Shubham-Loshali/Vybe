class DeveloperProfile {
  const DeveloperProfile({
    required this.name,
    required this.githubUrl,
    required this.linkedInUrl,
    this.photoAsset,
    this.photoScale = 1,
    this.photoAlignmentX = 0,
    this.photoAlignmentY = 0,
  });

  final String name;
  final String githubUrl;
  final String linkedInUrl;
  final String? photoAsset;
  final double photoScale;
  final double photoAlignmentX;
  final double photoAlignmentY;
}

const developerProfiles = [
  DeveloperProfile(
    name: 'Deepak Dumka',
    photoAsset: 'assets/images/developers/deepak.png',
    photoScale: 2.5,
    photoAlignmentX: 0.17,
    photoAlignmentY: -0.5,
    githubUrl: 'https://github.com/Deepakdumka1',
    linkedInUrl: 'https://www.linkedin.com/in/deepakdumka',
  ),
  DeveloperProfile(
    name: 'Shubham Loshali',
    photoAsset: 'assets/images/developers/shubham.png',
    photoScale: 2.4,
    photoAlignmentX: 0.24,
    photoAlignmentY: -0.45,
    githubUrl: 'https://github.com/Shubham-Loshali',
    linkedInUrl: 'https://www.linkedin.com/in/shubham-loshali',
  ),
];
