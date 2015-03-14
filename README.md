DP13_suka
=========


Not a problem which maps well to a GPU, but anyway still 3-5 times faster. Is a hybrid implementation.

NOTE: CPU version compiled with all optimizations (-O2) on a turbo 3.9 Ghz i7.

____
<table>
<tr>
    <th>Num spaces</th><th>CPU time</th><th>GPU time</th><th>CUDA Speedup</th>
</tr>

  <tr>
    <td>1000</td><td> 784 ms</td><td>  210 ms</td><td> 3.7x</td>
  </tr>
  <tr>
    <td>2000</td><td> 6,484 ms</td><td>  1,235 ms</td><td> 5.25x</td>
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
