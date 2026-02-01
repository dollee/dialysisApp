package com.example.dialysis_app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper

/**
 * 네이티브 전체화면 스플래시: 앱 실행 직후 전체화면 이미지가 바로 나오도록 함.
 * (Flutter 엔진 로딩 전에 표시되므로 녹색/단색 화면 없이 스플래시만 보임)
 * Theme.Light.NoTitleBar 사용을 위해 Activity 사용 (AppCompatActivity는 AppCompat 테마 필요)
 */
class SplashActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // setContentView 없이 테마의 windowBackground만 사용 (전체화면 drawable)

        Handler(Looper.getMainLooper()).postDelayed({
            startActivity(Intent(this, MainActivity::class.java))
            finish()
        }, 2800L) // 2.8초 후 Flutter MainActivity로
    }
}
