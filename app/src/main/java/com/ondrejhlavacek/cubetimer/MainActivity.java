package com.ondrejhlavacek.cubetimer;

import android.app.Activity;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.view.WindowInsets;
import android.widget.TextView;
import android.widget.PopupMenu;
import java.util.Locale;

public final class MainActivity extends Activity {
    private View surface;
    private TextView timer;
    private SharedPreferences preferences;
    private boolean running;
    private boolean finished;
    private long startedAt;
    private long elapsed;
    private int bootCount;
    private final Runnable ticker = new Runnable() {
        @Override public void run() {
            renderTime();
            if (running) surface.postOnAnimation(this);
        }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_main);
        surface = findViewById(R.id.surface);
        timer = findViewById(R.id.timer);
        int padding = getResources().getDimensionPixelSize(R.dimen.screen_padding);
        surface.setOnApplyWindowInsetsListener((view, insets) -> {
            int left = insets.getSystemWindowInsetLeft();
            int top = insets.getSystemWindowInsetTop();
            int right = insets.getSystemWindowInsetRight();
            int bottom = insets.getSystemWindowInsetBottom();
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                android.graphics.Insets bars = insets.getInsets(
                        WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                left = bars.left; top = bars.top; right = bars.right; bottom = bars.bottom;
            }
            view.setPadding(padding + left, padding + top, padding + right, padding + bottom);
            return insets;
        });
        preferences = getSharedPreferences("timer", MODE_PRIVATE);
        bootCount = Settings.Global.getInt(getContentResolver(), Settings.Global.BOOT_COUNT, -1);
        running = preferences.getBoolean("running", false);
        finished = preferences.getBoolean("finished", false);
        startedAt = preferences.getLong("startedAt", 0);
        elapsed = preferences.getLong("elapsed", 0);
        if (running && (bootCount == -1 || preferences.getInt("bootCount", -1) != bootCount
                || startedAt > SystemClock.elapsedRealtime())) {
            running = false;
            finished = false;
            elapsed = 0;
            persist();
        }
        surface.setOnClickListener(view -> toggle());
        findViewById(R.id.settings).setOnClickListener(this::showTimerMenu);
        renderState();
    }

    private void toggle() {
        long now = SystemClock.elapsedRealtime();
        if (running) {
            elapsed = now - startedAt;
            running = false;
            finished = true;
        } else {
            startedAt = now;
            elapsed = 0;
            running = true;
            finished = false;
        }
        onTimerChanged();
    }

    private void showTimerMenu(View anchor) {
        PopupMenu menu = new PopupMenu(this, anchor);
        menu.getMenu().add(0, R.string.resume, 0, R.string.resume).setEnabled(finished);
        menu.getMenu().add(0, R.string.reset, 1, R.string.reset).setEnabled(finished);
        menu.setOnMenuItemClickListener(item -> {
            if (item.getItemId() == R.string.resume) {
                startedAt = SystemClock.elapsedRealtime() - elapsed;
                running = true;
                finished = false;
            } else if (item.getItemId() == R.string.reset) {
                startedAt = 0;
                elapsed = 0;
                running = false;
                finished = false;
            } else {
                return false;
            }
            onTimerChanged();
            return true;
        });
        menu.show();
    }

    private void onTimerChanged() {
        persist();
        surface.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
        surface.removeCallbacks(ticker);
        renderState();
        if (running) surface.postOnAnimation(ticker);
        else surface.announceForAccessibility(surface.getContentDescription());
    }

    private void persist() {
        preferences.edit().putBoolean("running", running).putBoolean("finished", finished)
                .putLong("startedAt", startedAt).putLong("elapsed", elapsed)
                .putInt("bootCount", bootCount).apply();
    }

    private void renderState() {
        int color = getColor(running ? R.color.running_background : R.color.ready_background);
        surface.setBackgroundColor(color);
        surface.setKeepScreenOn(running);
        findViewById(R.id.settings).setVisibility(running ? View.INVISIBLE : View.VISIBLE);
        getWindow().setStatusBarColor(color);
        getWindow().setNavigationBarColor(color);
        ((TextView) findViewById(R.id.state)).setText(running ? R.string.solving : finished ? R.string.finished : R.string.ready);
        ((TextView) findViewById(R.id.icon)).setText(running ? R.string.stop_icon : R.string.play_icon);
        ((TextView) findViewById(R.id.action)).setText(running ? R.string.stop : finished ? R.string.again : R.string.start);
        ((TextView) findViewById(R.id.hint)).setText(running ? R.string.stop_hint : R.string.start_hint);
        renderTime();
        surface.setContentDescription(running ? getString(R.string.running_accessibility)
                : finished ? getString(R.string.finished_accessibility, timer.getText())
                : getString(R.string.ready_accessibility));
    }

    private void renderTime() {
        long centiseconds = (running ? SystemClock.elapsedRealtime() - startedAt : elapsed) / 10;
        timer.setText(String.format(Locale.US, "%02d:%02d.%02d",
                centiseconds / 6000, centiseconds / 100 % 60, centiseconds % 100));
    }

    @Override protected void onResume() {
        super.onResume();
        surface.removeCallbacks(ticker);
        ticker.run();
    }

    @Override protected void onPause() {
        surface.removeCallbacks(ticker);
        super.onPause();
    }
}
