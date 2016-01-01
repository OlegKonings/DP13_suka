DP13_suka
=========


Not a problem which maps well to a GPU, but anyway still 7-9 times faster despite the fact that computation is done in 64 bit using a GTX GPU. 
Did not even try to coalesce memory updates, and could improve quite a bit with some effort.

NOTE: CPU version compiled with all optimizations (-O2) on a  4.5 Ghz i7-4820. GPU GTX Titan X 1.1 GHz with --use_fast_math

____
<table>
<tr>
    <th>Num spaces</th><th>CPU time</th><th>GPU time</th><th>CUDA Speedup</th>
</tr>

  <tr>
    <td>1000</td><td> 626 ms</td><td>  84 ms</td><td> 7.4x</td>
  </tr>
  <tr>
    <td>2000</td><td> 5,988 ms</td><td>  588 ms</td><td> 10.18x</td>
  </tr>
</table>  
___  


<script>
  (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
  (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
  m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
  })(window,document,'script','//www.google-analytics.com/analytics.js','ga');

  ga('create', 'UA-60172288-1', 'auto');
  ga('send', 'pageview');

</script>
