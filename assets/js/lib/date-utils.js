export function secondsToTime(_seconds) {
  let hours   = Math.floor(_seconds / 3600);
  let minutes = Math.floor((_seconds - (hours * 3600)) / 60);
  let seconds = _seconds - (hours * 3600) - (minutes * 60);
  let time = "";

  if (hours !== 0) {
    time = hours+":";
  }
  if (minutes !== 0 || time !== "") {
    minutes = (minutes < 10 && time !== "") ? "0"+minutes : String(minutes);
    time += minutes+":";
  } else {
    time += "0:"
  }
  if (time === "") {
    time = seconds;
  }
  else {
    time += (seconds < 10) ? "0"+seconds : String(seconds);
  }
  return time;
}
