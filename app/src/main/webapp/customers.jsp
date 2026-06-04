<%@ page contentType="text/html;charset=UTF-8" %>
<%@ taglib prefix="s" uri="/struts-tags" %>
<html>
<head><title>Customers</title></head>
<body style="font-family: sans-serif; max-width: 600px; margin: 40px auto;">
  <h1>Recent Customers</h1>
  <ul>
    <s:iterator value="customers">
      <li><s:property/></li>
    </s:iterator>
  </ul>
  <p><a href="index.jsp">Back</a></p>
</body>
</html>
