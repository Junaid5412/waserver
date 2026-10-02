// LiteSpeed requires this entry synchronously. Keep asynchronous dependencies
// behind import() so its CommonJS loader can initialize the app.
import("./application.js").catch(async (error) => {
  if (error.code === "ZELON_WORKER_BUSY") {
    try {
      const { startFollower } = await import("./follower.js");
      await startFollower();
      return;
    } catch (failure) {
      error = failure;
    }
  }
  console.error("Zelon API startup failed:", error);
  process.exit(1);
});
