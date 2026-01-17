# dialysis_app

투석 기록/체중/혈압을 Google Sheets에 월별로 저장하고, 모바일 건강데이터와 연동하는 Flutter 앱입니다.

## 필수 설정

### OAuth 2.0 클라이언트
- Google Cloud Console에서 OAuth 2.0 클라이언트 ID/Secret 생성
- Replit에서 제공하는 Redirect URL을 승인된 리디렉션 URI에 등록

### Secrets 저장
- `CLIENT_ID`와 `CLIENT_SECRET`을 FlutterFlow Secrets 도구에 저장

### 건강 데이터 권한
- Android: `android/app/src/main/AndroidManifest.xml`에 Health Connect 권한 추가
- iOS: `ios/Runner/Info.plist`에 `NSHealthShareUsageDescription` 및 `NSHealthUpdateUsageDescription` 추가

## 실행

```
flutter pub get
flutter run
```
