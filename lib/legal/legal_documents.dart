/// 앱 안에서 보여주는 법적 문서. 같은 파일이 웹(GitHub Pages)에도 올라간다.
enum LegalDocument {
  privacyPolicy('개인정보처리방침', 'docs/privacy-policy.md'),
  locationTerms('위치기반서비스 이용약관', 'docs/location-terms.md');

  const LegalDocument(this.title, this.assetPath);

  final String title;
  final String assetPath;
}

/// 앱이 쓰는 데이터의 출처. 공공데이터 이용 조건에 따라 표시한다.
const dataSources = [
  (name: '대중교통 길찾기, 버스 노선 정보', via: 'ODsay LAB (lab.odsay.com)'),
  (name: '국토교통부 (TAGO) 버스·지하철 정보', via: '공공데이터포털 (data.go.kr)'),
  (name: '서울시 지하철 실시간 정보', via: '서울 열린데이터광장 (data.seoul.go.kr)'),
];
