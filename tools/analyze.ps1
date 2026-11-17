# analyze.ps1 - quick objective check of a rendered WAV (PCM 16/24-bit or float32)
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\analyze.ps1 renders\x.wav
# Prints peak / RMS / crest, energy per frequency band (relative to the loudest band),
# and the strongest spectral peaks.
param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System; using System.IO; using System.Collections.Generic; using System.Text;
public static class Ana {
  static void Fft(double[] re, double[] im) {
    int n = re.Length;
    for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; (j & bit) != 0; bit >>= 1) j ^= bit; j ^= bit;
      if (i < j) { var t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; } }
    for (int len = 2; len <= n; len <<= 1) { double ang = -2 * Math.PI / len; double wr = Math.Cos(ang), wi = Math.Sin(ang);
      for (int i = 0; i < n; i += len) { double cr = 1, ci = 0;
        for (int k = 0; k < len / 2; k++) { int a = i + k, b = a + len / 2;
          double xr = re[b] * cr - im[b] * ci, xi = re[b] * ci + im[b] * cr;
          re[b] = re[a] - xr; im[b] = im[a] - xi; re[a] += xr; im[a] += xi;
          double nr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = nr; } } }
  }
  public static string Run(string path) {
    var br = new BinaryReader(File.OpenRead(path));
    br.ReadBytes(12); int ch = 0, rate = 0, bits = 0, fmt = 0; byte[] data = null;
    while (br.BaseStream.Position < br.BaseStream.Length) {
      string id = Encoding.ASCII.GetString(br.ReadBytes(4)); int size = br.ReadInt32();
      if (id == "fmt ") { fmt = br.ReadInt16(); ch = br.ReadInt16(); rate = br.ReadInt32(); br.ReadBytes(6); bits = br.ReadInt16(); br.ReadBytes(size - 16); }
      else if (id == "data") { data = br.ReadBytes(size); break; }
      else br.ReadBytes(size + (size & 1));
    }
    int bps = bits / 8, frames = data.Length / (bps * ch);
    var x = new double[frames]; var L = new double[frames]; var R = new double[frames];
    for (int f = 0; f < frames; f++) { double s = 0;
      for (int c = 0; c < ch; c++) { int o = (f * ch + c) * bps; double v;
        if (fmt == 3) v = BitConverter.ToSingle(data, o);
        else if (bits == 16) v = BitConverter.ToInt16(data, o) / 32768.0;
        else if (bits == 24) v = ((data[o] | (data[o + 1] << 8) | ((sbyte)data[o + 2] << 16))) / 8388608.0;
        else v = BitConverter.ToInt32(data, o) / 2147483648.0;
        if (c == 0) L[f] = v; if (c == (ch > 1 ? 1 : 0)) R[f] = v;
        s += v; }
      x[f] = s / ch; }
    // true sample peak / RMS over all channels (not of the mono fold-down used for the spectrum)
    double peak = 0, sum = 0;
    for (int f = 0; f < frames; f++) { peak = Math.Max(peak, Math.Max(Math.Abs(L[f]), Math.Abs(R[f]))); sum += (L[f] * L[f] + R[f] * R[f]) / 2; }
    double rms = Math.Sqrt(sum / frames);
    int N = 8192; var spec = new double[N / 2]; int segs = 0;
    var win = new double[N]; for (int i = 0; i < N; i++) win[i] = 0.5 - 0.5 * Math.Cos(2 * Math.PI * i / (N - 1));
    for (int st = 0; st + N <= frames; st += N / 2) {
      var re = new double[N]; var im = new double[N];
      for (int i = 0; i < N; i++) re[i] = x[st + i] * win[i];
      Fft(re, im); for (int k = 0; k < N / 2; k++) spec[k] += re[k] * re[k] + im[k] * im[k]; segs++; }
    double[] edges = { 20, 150, 300, 500, 1000, 2000, 4000, 8000, 22050 };
    var band = new double[edges.Length - 1];
    for (int k = 1; k < N / 2; k++) { double fq = (double)k * rate / N;
      for (int b = 0; b < band.Length; b++) if (fq >= edges[b] && fq < edges[b + 1]) band[b] += spec[k]; }
    double bmax = 0; foreach (var b in band) bmax = Math.Max(bmax, b);
    var sb = new StringBuilder();
    sb.AppendFormat("file: {0}\nformat: {1} Hz, {2} ch, {3}-bit, {4:F1} s\n", Path.GetFileName(path), rate, ch, bits, frames / (double)rate);
    sb.AppendFormat("peak: {0:F1} dBFS   rms: {1:F1} dBFS   crest: {2:F1} dB\n", 20 * Math.Log10(peak + 1e-12), 20 * Math.Log10(rms + 1e-12), 20 * Math.Log10((peak + 1e-12) / (rms + 1e-12)));
    sb.Append("band energy (dB rel. loudest band):\n");
    for (int b = 0; b < band.Length; b++) {
      double db = 10 * Math.Log10(band[b] / bmax + 1e-15);
      int bars = Math.Max(0, (int)Math.Round((db + 60) / 2));
      sb.AppendFormat("  {0,5}-{1,-5} Hz {2,7:F1}  {3}\n", edges[b], edges[b + 1], db, new string('#', bars)); }
    var peaks = new List<KeyValuePair<double, double>>();
    for (int k = 2; k < N / 2 - 2; k++) if (spec[k] > spec[k - 1] && spec[k] >= spec[k + 1] && spec[k] > spec[k - 2] && spec[k] >= spec[k + 2]) peaks.Add(new KeyValuePair<double, double>((double)k * rate / N, spec[k]));
    peaks.Sort((a, b) => b.Value.CompareTo(a.Value)); double top = peaks.Count > 0 ? peaks[0].Value : 1;
    sb.Append("strongest peaks: ");
    for (int i = 0; i < Math.Min(10, peaks.Count); i++) sb.AppendFormat("{0:F0}Hz({1:F0}dB) ", peaks[i].Key, 10 * Math.Log10(peaks[i].Value / top));
    // timeline: per segment level, L/R balance, side/mid (width)
    int seg = rate * 3;
    sb.Append("\ntimeline (3 s): time  rms dBFS  L-R dB  side/mid dB\n");
    for (int st = 0; st < frames; st += seg) {
      int en = Math.Min(frames, st + seg); double sl = 0, sr = 0, sm = 0, ss = 0;
      for (int f = st; f < en; f++) { sl += L[f] * L[f]; sr += R[f] * R[f]; double m = (L[f] + R[f]) / 2, d = (L[f] - R[f]) / 2; sm += m * m; ss += d * d; }
      int n = en - st;
      sb.AppendFormat("  {0,5:F0}s  {1,7:F1}  {2,6:F1}  {3,8:F1}\n", st / (double)rate,
        10 * Math.Log10((sl + sr) / (2.0 * n) + 1e-15), 10 * Math.Log10((sl + 1e-15) / (sr + 1e-15)), 10 * Math.Log10((ss + 1e-15) / (sm + 1e-15))); }
    return sb.ToString();
  }
}
'@
[Ana]::Run((Resolve-Path $Path).Path)
