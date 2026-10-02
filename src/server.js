// LiteSpeed loads this entry with require(). Keep its ESM graph synchronous;
// load the application and its asynchronous dependencies through import().
import("./application.js").catch((error) => {
  console.error("Zelon API startup failed:", error);
  process.exit(1);
});
