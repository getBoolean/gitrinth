import 'package:gitrinth/src/service/curseforge_url.dart';
import 'package:gitrinth/src/service/modrinth_url.dart';
import 'package:test/test.dart';

void main() {
  group('defaultCurseForgeBaseUrl', () {
    test('is api.curseforge.com without a trailing slash', () {
      expect(defaultCurseForgeBaseUrl, 'https://api.curseforge.com');
      expect(defaultCurseForgeBaseUrl.endsWith('/'), isFalse);
    });
  });

  group('resolveCurseForgeBaseUrl', () {
    test('strips trailing slash from GITRINTH_CURSEFORGE_URL', () {
      expect(
        resolveCurseForgeBaseUrl({'GITRINTH_CURSEFORGE_URL': 'http://x/'}),
        'http://x',
      );
    });

    test(
      'returns the env value verbatim when no trailing slash is present',
      () {
        expect(
          resolveCurseForgeBaseUrl({
            'GITRINTH_CURSEFORGE_URL': 'https://cf.example.com',
          }),
          'https://cf.example.com',
        );
      },
    );

    test('falls back to defaultCurseForgeBaseUrl when env is unset', () {
      expect(resolveCurseForgeBaseUrl(const {}), defaultCurseForgeBaseUrl);
    });

    test('falls back when env value is empty', () {
      expect(
        resolveCurseForgeBaseUrl({'GITRINTH_CURSEFORGE_URL': ''}),
        defaultCurseForgeBaseUrl,
      );
    });
  });

  group('decodeDefaultCfApiKey', () {
    test('returns empty when no build-time key is embedded', () {
      expect(decodeDefaultCfApiKey(), isEmpty);
    });
  });

  group('upload-API constants', () {
    test('defaultCurseForgeUploadBaseUrl is minecraft.curseforge.com without a '
        'trailing slash', () {
      expect(
        defaultCurseForgeUploadBaseUrl,
        'https://minecraft.curseforge.com',
      );
      expect(defaultCurseForgeUploadBaseUrl.endsWith('/'), isFalse);
    });

    test('curseForgeUploadTokenKey is managed as curseforge.com', () {
      expect(
        curseForgeUploadTokenKey,
        normalizeServerKey('https://curseforge.com'),
      );
    });

    test('curseForgeUploadTokenKey is distinct from the read API host', () {
      expect(
        curseForgeUploadTokenKey,
        isNot(equals(normalizeServerKey(defaultCurseForgeBaseUrl))),
      );
    });
  });

  group('resolveCurseForgeUploadToken', () {
    test('returns the env value when present', () {
      expect(
        resolveCurseForgeUploadToken(
          env: const {'GITRINTH_CURSEFORGE_UPLOAD_TOKEN': 'env-upload'},
          userTokens: const {},
        ),
        'env-upload',
      );
    });

    test('falls back to userTokens[curseForgeUploadTokenKey]', () {
      expect(
        resolveCurseForgeUploadToken(
          env: const {},
          userTokens: {curseForgeUploadTokenKey: 'user-upload'},
        ),
        'user-upload',
      );
    });

    test('env wins over userTokens', () {
      expect(
        resolveCurseForgeUploadToken(
          env: const {'GITRINTH_CURSEFORGE_UPLOAD_TOKEN': 'env-upload'},
          userTokens: {curseForgeUploadTokenKey: 'user-upload'},
        ),
        'env-upload',
      );
    });

    test('returns null when neither env nor userTokens has a value', () {
      expect(
        resolveCurseForgeUploadToken(env: const {}, userTokens: const {}),
        isNull,
      );
    });

    test('treats empty strings as missing', () {
      expect(
        resolveCurseForgeUploadToken(
          env: const {'GITRINTH_CURSEFORGE_UPLOAD_TOKEN': ''},
          userTokens: {curseForgeUploadTokenKey: ''},
        ),
        isNull,
      );
    });
  });
}
