{{flutter_js}}
{{flutter_build_config}}

(() => {
  let bootFinished = false;
  const timeout = window.setTimeout(() => {
    if (bootFinished) return;
    showFlutterBootstrapError(
      '앱 시작이 지연되고 있어요. 네트워크 연결을 확인한 뒤 다시 시도해주세요.',
    );
  }, 15000);

  const fail = (error) => {
    if (bootFinished) return;
    window.clearTimeout(timeout);
    console.error('Setflow Flutter bootstrap failed', error);
    showFlutterBootstrapError(
      '앱 초기화 중 문제가 발생했어요. 잠시 후 다시 시도해주세요.',
    );
  };

  window.addEventListener('error', (event) => {
    // Resource failures have no Error object and can be non-critical. Only a
    // JavaScript exception before the app starts should replace the splash.
    if (event.error) fail(event.error);
  });
  window.addEventListener('unhandledrejection', (event) => fail(event.reason));

  const loading = _flutter.loader.load({
    onEntrypointLoaded: async (engineInitializer) => {
      try {
        const appRunner = await engineInitializer.initializeEngine();
        await appRunner.runApp();
        bootFinished = true;
        window.clearTimeout(timeout);
        finishFlutterBootstrap();
      } catch (error) {
        fail(error);
      }
    },
  });

  Promise.resolve(loading).catch(fail);
})();
